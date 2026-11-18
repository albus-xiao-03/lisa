// Integration and recovery tests for L32, successive notification revisions (NOTIFY-03, NOTIFY-01, REM-03, CAL-02;
// plan §6.4; D-07, D-26, D-27): two successive important changes to one near calendar event are two notification
// occurrences, and each reaches every enabled device — the Mac's notification center and an iPhone and an iPad over
// APNs — exactly once, with the same collapse identity so the newer replaces the older on the device. That holds
// across a provider's temporary failures, a restart with retries pending, and a restart while a retry was claimed but
// not yet sent. Changes still pending coalesce into the latest one, while a change made after an earlier delivery is
// never coalesced away. Pushes go through the real APNs adapter to a scripted stand-in for Apple; the Mac's
// notification center is a scripted substitute; devices pair through the API with random tokens.

import Foundation
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L32 — Successive notification revisions")
struct L32SuccessiveNotificationRevisionsTests {
    private let event = SyntheticEvent(
        uid: "revisions-review@example.com", title: "Synthetic budget review", start: "2026-11-16T10:00",
        end: "2026-11-16T11:00")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Brief availability is not notified, so the event's changes are the only notifications.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        return owner
    }

    /// A host with the calendar file, the Mac's installation and two devices that push through APNs.
    private struct Scenario {
        var testHost: TestHost
        var host: LisaHost
        var live: LivePush
        var center: ScriptedNotificationCenter
        var file: URL
        var mac: DeviceID
        var phoneID: DeviceID
        var padID: DeviceID
        var phoneToken: String
        var padToken: String
    }

    /// Opens the host at `time` with the 10:00 event in its calendar, pairs the devices and runs the first cycle,
    /// which stores the event without notifying anything.
    private func scenario(
        _ scratch: ScratchDirectory, at time: String, center: ScriptedNotificationCenter
    ) async throws -> Scenario {
        let file = scratch.path("calendars", "work.ics")
        try SourceFiles.write(SyntheticEvent.calendar([event]), to: file, modifiedAt: at(time))
        let live = try await LivePush()
        var testHost = TestHost(
            scratch: scratch, now: at(time), owner: owner(), sources: [SourceFiles.calendarSource(file)],
            localNotifications: center)
        live.configure(&testHost)
        let host = try live.open(testHost)
        let mac = try TestHost.registerMac(on: host)
        let ownerClient = OwnerClient.inProcess(host)
        let phone = try SyntheticCompanion(
            "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
        let pad = try SyntheticCompanion(
            "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport, clock: testHost.clock)
        let phoneID = try await phone.pair(codeFrom: ownerClient)
        let padID = try await pad.pair(codeFrom: ownerClient)
        await host.runtime.runOnce()
        #expect(try host.application.all(CalendarOccurrence.self).count == 1)
        // The brief's availability is recorded but not routed, so no device has a delivery yet.
        #expect(try host.application.all(NotificationIntent.self).allSatisfy { $0.category == .brief })
        #expect(try host.application.all(Delivery.self).allSatisfy { $0.channel == .email })
        return Scenario(
            testHost: testHost, host: host, live: live, center: center, file: file, mac: mac,
            phoneID: DeviceID(phoneID), padID: DeviceID(padID),
            phoneToken: try #require(try LivePush.token(of: phoneID, in: host)),
            padToken: try #require(try LivePush.token(of: padID, in: host)))
    }

    /// Moves the event to start at `start` (for an hour) in the calendar file, then runs a cycle at `time`, after the
    /// source's interval, so the synchronization finds the change.
    private func move(to start: String, at time: String, _ scenario: Scenario) async throws {
        var moved = event
        moved.start = "2026-11-16T\(start)"
        let hour = Int(start.prefix(2)) ?? 0
        moved.end = "2026-11-16T\(String(format: "%02d", hour + 1))\(start.dropFirst(2))"
        try SourceFiles.write(SyntheticEvent.calendar([moved]), to: scenario.file, modifiedAt: at(time))
        await cycle(scenario, at: time)
    }

    private func cycle(_ scenario: Scenario, at time: String) async {
        scenario.testHost.clock.set(at(time))
        await scenario.host.runtime.runOnce()
    }

    /// The event's change occurrences, oldest change first.
    private func changes(_ scenario: Scenario) throws -> [NotificationIntent] {
        try scenario.host.application.all(NotificationIntent.self).filter { $0.category == .commitmentChange }
            .sorted { $0.changeSequence < $1.changeSequence }
    }

    private func delivery(of intent: NotificationIntent, to device: DeviceID, _ scenario: Scenario) throws -> Delivery?
    {
        try scenario.host.application.all(Delivery.self).first {
            $0.payload == .notification(intent.id) && $0.recipient == .device(device)
        }
    }

    /// How often `intent` was handed to each device's transport, and how often it was accepted there.
    private struct Transmissions: Equatable, CustomStringConvertible {
        var sent: Int
        var accepted: Int
        var description: String { "sent \(sent), accepted \(accepted)" }
    }

    private func transmissions(of intent: NotificationIntent, _ scenario: Scenario) throws -> [DeviceID: Transmissions]
    {
        let presented = scenario.center.presented.filter { $0.presentation.notificationID == intent.id.rawValue }
        let macAccepted = try delivery(of: intent, to: scenario.mac, scenario)?.state == .acceptedByProvider ? 1 : 0
        let phone = scenario.live.apns.exchanges(to: scenario.phoneToken, about: intent.id.rawValue)
        let pad = scenario.live.apns.exchanges(to: scenario.padToken, about: intent.id.rawValue)
        return [
            scenario.mac: Transmissions(sent: presented.count, accepted: macAccepted),
            scenario.phoneID: Transmissions(sent: phone.count, accepted: phone.filter(\.wasAccepted).count),
            scenario.padID: Transmissions(sent: pad.count, accepted: pad.filter(\.wasAccepted).count),
        ]
    }

    /// Checks that `intent` was accepted exactly once on every device, each delivery ending accepted.
    private func expectAcceptedOnceEverywhere(
        _ intent: NotificationIntent, _ scenario: Scenario, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for (device, counted) in try transmissions(of: intent, scenario) {
            #expect(counted.accepted == 1, "\(device.rawValue): \(counted)", sourceLocation: sourceLocation)
            let state = try delivery(of: intent, to: device, scenario)?.state
            #expect(state == .acceptedByProvider, "\(device.rawValue)", sourceLocation: sourceLocation)
        }
    }

    @Test("Two successive important changes each reach every enabled device once", .tags(.integration))
    func successiveChangesEachReachEveryDevice() async throws {
        try await ScratchDirectory.with { scratch in
            let scenario = try await scenario(scratch, at: "08:00", center: ScriptedNotificationCenter())
            try await move(to: "10:30", at: "08:06", scenario)
            let afterFirst = try changes(scenario)
            #expect(afterFirst.count == 1)
            let first = try #require(afterFirst.first)
            try expectAcceptedOnceEverywhere(first, scenario)

            try await move(to: "11:00", at: "08:12", scenario)
            let both = try changes(scenario)
            #expect(both.count == 2)
            let second = try #require(both.last)
            #expect(second.id != first.id)
            #expect(second.changeSequence == first.changeSequence + 1)
            #expect(second.subject == first.subject)
            #expect(second.collapseKey == first.collapseKey)
            // The earlier change was delivered, so it is still a notification of its own.
            #expect(both.map(\.state) == [.active, .active])
            try expectAcceptedOnceEverywhere(first, scenario)
            try expectAcceptedOnceEverywhere(second, scenario)

            // Both pushes to a device share one collapse identity, so the newer replaces the older there; each
            // carries its own notification and the event's revision when it was sent.
            let pushes = scenario.live.apns.exchanges(to: scenario.phoneToken)
            #expect(pushes.compactMap { $0.lisa?.notificationID } == [first.id.rawValue, second.id.rawValue])
            #expect(Set(pushes.compactMap { $0.header("apns-collapse-id") }).count == 1)
            let revisions = pushes.compactMap { $0.lisa?.subjectRevision }
            #expect(revisions.count == 2 && revisions[0] < revisions[1])

            // Later cycles repeat nothing.
            await cycle(scenario, at: "08:18")
            await cycle(scenario, at: "08:30")
            for intent in [first, second] {
                for (device, counted) in try transmissions(of: intent, scenario) {
                    #expect(counted == Transmissions(sent: 1, accepted: 1), "\(device.rawValue)")
                }
            }
            #expect(scenario.live.apns.exchanges.count == 4)
            scenario.host.close()
        }
    }

    @Test(
        "Pending changes coalesce into the latest, and a change after an earlier delivery is never coalesced away",
        .tags(.integration))
    func pendingChangesCoalesce() async throws {
        try await ScratchDirectory.with { scratch in
            // Before 07:00 quiet hours hold every delivery back, so nothing is submitted until then.
            let scenario = try await scenario(scratch, at: "06:00", center: ScriptedNotificationCenter())
            try await move(to: "10:30", at: "06:06", scenario)
            let held = try #require(try changes(scenario).first)
            for device in [scenario.mac, scenario.phoneID, scenario.padID] {
                let pending = try delivery(of: held, to: device, scenario)
                #expect(pending?.state == .pending)
                #expect(pending?.stateReason == "deferred until quiet hours end")
            }

            try await move(to: "11:00", at: "06:12", scenario)
            let both = try changes(scenario)
            #expect(both.count == 2)
            let coalesced = try #require(both.first)
            let latest = try #require(both.last)
            #expect(coalesced.id == held.id)
            #expect(coalesced.state == .coalesced)
            #expect(latest.state == .active)
            for device in [scenario.mac, scenario.phoneID, scenario.padID] {
                let suppressed = try delivery(of: coalesced, to: device, scenario)
                #expect(suppressed?.state == .suppressed)
                #expect(suppressed?.stateReason == "coalesced into a later change")
                #expect(try delivery(of: latest, to: device, scenario)?.state == .pending)
            }

            // At 07:00 only the latest change goes out, once to every device; the coalesced one never does.
            await cycle(scenario, at: "07:00")
            try expectAcceptedOnceEverywhere(latest, scenario)
            for (device, counted) in try transmissions(of: coalesced, scenario) {
                #expect(counted == Transmissions(sent: 0, accepted: 0), "\(device.rawValue)")
            }

            // A change after that delivery is a new notification, and the delivered one is left alone.
            try await move(to: "11:30", at: "07:06", scenario)
            let all = try changes(scenario)
            #expect(all.count == 3)
            let third = try #require(all.last)
            #expect(all.map(\.state) == [.coalesced, .active, .active])
            try expectAcceptedOnceEverywhere(latest, scenario)
            try expectAcceptedOnceEverywhere(third, scenario)
            #expect(scenario.live.apns.exchanges.count == 4)
            scenario.host.close()
        }
    }

    @Test(
        "Across provider retries and restarts, each of two successive changes reaches every device once",
        .tags(.recovery))
    func successiveChangesAcrossRetriesAndRestarts() async throws {
        try await ScratchDirectory.with { scratch in
            // The Mac's first presentation fails for the moment, and APNs answers the iPhone's first push with 503.
            let center = ScriptedNotificationCenter(steps: [
                .answer(.temporarilyUnavailable(reason: "the synthetic notification center is busy", retryAfter: nil))
            ])
            var scenario = try await scenario(scratch, at: "08:00", center: center)
            scenario.live.apns.script(
                [.refused(status: 503, reason: "ServiceUnavailable")], forToken: scenario.phoneToken)
            try await move(to: "10:30", at: "08:06", scenario)
            let first = try #require(try changes(scenario).first)
            #expect(try delivery(of: first, to: scenario.mac, scenario)?.state == .pending)
            let waiting = try #require(try delivery(of: first, to: scenario.phoneID, scenario))
            #expect(waiting.state == .pending)
            // APNs asks for at least 15 minutes before a retry after a server error.
            #expect(waiting.nextAttemptAt >= at("08:21"))
            #expect(try delivery(of: first, to: scenario.padID, scenario)?.state == .acceptedByProvider)

            // The host restarts with both retries pending; the Mac's comes due first.
            scenario.testHost.clock.set(at("08:07"))
            try scenario.live.restart(scenario.testHost, &scenario.host)
            await cycle(scenario, at: "08:08")
            #expect(try delivery(of: first, to: scenario.mac, scenario)?.state == .acceptedByProvider)

            // A second change while the iPhone still waits: the first was submitted, so it is not coalesced.
            try await move(to: "11:00", at: "08:12", scenario)
            let both = try changes(scenario)
            #expect(both.count == 2)
            let second = try #require(both.last)
            #expect(both.map(\.state) == [.active, .active])
            try expectAcceptedOnceEverywhere(second, scenario)
            #expect(try delivery(of: first, to: scenario.phoneID, scenario)?.state == .pending)

            // 08:22: the iPhone's retry is claimed, and the host stops before preparing or sending it.
            scenario.testHost.clock.set(at("08:22"))
            let claimed = try scenario.host.application.services.outbox.claimDue()
            #expect(claimed.map(\.id) == [waiting.id])
            try scenario.live.restart(scenario.testHost, &scenario.host)
            // Once its lease has expired, the claimed retry is made again, once.
            await cycle(scenario, at: "08:25")
            let retried = try #require(try delivery(of: first, to: scenario.phoneID, scenario))
            #expect(retried.state == .acceptedByProvider)
            #expect(retried.attempts.count == 3)
            #expect(retried.attempts.dropFirst().first?.result == "lease expired before submission")

            // Another restart and later cycles repeat nothing.
            try scenario.live.restart(scenario.testHost, &scenario.host)
            await cycle(scenario, at: "08:30")
            await cycle(scenario, at: "08:45")
            try expectAcceptedOnceEverywhere(first, scenario)
            try expectAcceptedOnceEverywhere(second, scenario)
            let firstCounts = try transmissions(of: first, scenario)
            #expect(firstCounts[scenario.mac] == Transmissions(sent: 2, accepted: 1))
            #expect(firstCounts[scenario.phoneID] == Transmissions(sent: 2, accepted: 1))
            #expect(firstCounts[scenario.padID] == Transmissions(sent: 1, accepted: 1))
            for (device, counted) in try transmissions(of: second, scenario) {
                #expect(counted == Transmissions(sent: 1, accepted: 1), "\(device.rawValue)")
            }
            scenario.host.close()
        }
    }
}
