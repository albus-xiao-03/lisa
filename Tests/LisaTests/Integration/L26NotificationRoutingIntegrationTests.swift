// Integration tests for L26, notification routing at integration level (NOTIFY-01, NOTIFY-03, NOTIFY-05, REM-02;
// plan §6.1, §6.5; D-26, D-27), through the real host: a due reminder, an important change to a near calendar event
// and the daily brief's availability each reach every enabled device by default — the Mac's own notification center
// and a paired iPhone and iPad — with one delivery record per device. A device that turns a category or all of its
// notifications off, or reports notification permission denied (also between the decision and the send), gets a
// suppressed record with the reason and shows in health, and receives again once it turns them back on. Quiet hours
// defer every device's delivery to their end, or let it expire, with the reason recorded. The Mac's notification
// center is a scripted substitute, pushes are dry runs, and devices pair through the API with random tokens.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDelivery
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L26 — Notification routing (integration)", .tags(.integration))
struct L26NotificationRoutingIntegrationTests {
    private let event = SyntheticEvent(
        uid: "routing-review@example.com", title: "Synthetic design review", start: "2026-11-16T10:00",
        end: "2026-11-16T11:00")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// The brief is ready at 07:30, and its availability is notified only when `briefNotifications` is set.
    private func owner(briefNotifications: Bool = false) -> OwnerSettings {
        var owner = TestHost.owner()
        owner.brief.deliveryTime = TestTime.time("07:30")
        owner.notifications.notifyBriefAvailability = briefNotifications
        return owner
    }

    /// The Mac's own installation and a paired iPhone and iPad.
    private struct Devices {
        var mac: DeviceID
        var phone: SyntheticCompanion
        var pad: SyntheticCompanion
        var phoneID: DeviceID
        var padID: DeviceID

        var all: Set<DeviceID> { [mac, phoneID, padID] }
    }

    /// A host at `time` with the calendar file holding the 10:00 event, the Mac's installation, and an iPhone and an
    /// iPad paired through the API with random tokens and notifications allowed.
    private func openHost(
        _ scratch: ScratchDirectory, at time: String, owner: OwnerSettings, center: ScriptedNotificationCenter
    ) async throws -> (TestHost, LisaHost, Devices, URL) {
        let file = scratch.path("calendars", "work.ics")
        try SourceFiles.write(SyntheticEvent.calendar([event]), to: file, modifiedAt: at("06:00"))
        let testHost = TestHost(
            scratch: scratch, now: at(time), owner: owner, sources: [SourceFiles.calendarSource(file)],
            localNotifications: center)
        let host = try testHost.open()
        let mac = try TestHost.registerMac(on: host)
        let ownerClient = OwnerClient.inProcess(host)
        let phone = try SyntheticCompanion(
            "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
        let pad = try SyntheticCompanion(
            "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport, clock: testHost.clock)
        let phoneID = DeviceID(try await phone.pair(codeFrom: ownerClient))
        let padID = DeviceID(try await pad.pair(codeFrom: ownerClient))
        let devices = Devices(mac: mac, phone: phone, pad: pad, phoneID: phoneID, padID: padID)
        return (testHost, host, devices, file)
    }

    private func cycle(_ host: LisaHost, _ testHost: TestHost, at time: String) async {
        testHost.clock.set(at(time))
        await host.runtime.runOnce()
    }

    /// Moves the event in the calendar file to `start`–`end`; the next synchronization finds the change.
    private func moveEvent(to start: String, _ end: String, file: URL, _ testHost: TestHost) throws {
        var moved = event
        moved.start = "2026-11-16T\(start)"
        moved.end = "2026-11-16T\(end)"
        try SourceFiles.write(SyntheticEvent.calendar([moved]), to: file, modifiedAt: testHost.clock.now())
    }

    /// A confirmed task due at `deadline`.
    private func task(_ title: String, due deadline: String, on host: LisaHost) throws -> LisaTask {
        try host.application.createTask(
            TaskDraft(title: title, deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    /// The notification occurrences of `category`.
    private func intents(_ category: NotificationCategory, in host: LisaHost) throws -> [NotificationIntent] {
        try host.application.all(NotificationIntent.self).filter { $0.category == category }
    }

    /// The one reminder notification of `task`.
    private func reminderIntent(of task: LisaTask, in host: LisaHost) throws -> NotificationIntent {
        let found = try TaskNotifications.occurrences(of: task.id, in: host)
        #expect(found.count == 1)
        return try #require(found.first)
    }

    /// The deliveries of `intent`, by device.
    private func deliveries(of intent: NotificationIntent, in host: LisaHost) throws -> [DeviceID: Delivery] {
        var byDevice: [DeviceID: Delivery] = [:]
        for delivery in try host.application.all(Delivery.self) where delivery.payload == .notification(intent.id) {
            guard case .device(let id) = delivery.recipient else { continue }
            #expect(byDevice[id] == nil, "two deliveries of one notification for one device")
            byDevice[id] = delivery
        }
        return byDevice
    }

    /// How often `intent` reached each device: presentations by the Mac's center, dry-run push captures otherwise.
    private func receipts(
        of intent: NotificationIntent, _ devices: Devices, host: LisaHost, center: ScriptedNotificationCenter
    ) throws -> [DeviceID: Int] {
        let byDevice = try deliveries(of: intent, in: host)
        let captures = try host.recorder.recent(limit: 1_000).filter { $0.channel == .push }
        var counts: [DeviceID: Int] = [:]
        counts[devices.mac] = center.presented.filter { $0.presentation.notificationID == intent.id.rawValue }.count
        for id in [devices.phoneID, devices.padID] {
            let matching = captures.filter { $0.reference == byDevice[id]?.id.rawValue }
            #expect(matching.allSatisfy { $0.content.contains("notification=\(intent.id.rawValue)") })
            counts[id] = matching.count
        }
        return counts
    }

    /// Checks that `intent` has a delivery for every device and reached each of them exactly once.
    private func expectReachedEveryDevice(
        _ intent: NotificationIntent, _ devices: Devices, host: LisaHost, center: ScriptedNotificationCenter,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let byDevice = try deliveries(of: intent, in: host)
        #expect(Set(byDevice.keys) == devices.all, sourceLocation: sourceLocation)
        #expect(byDevice[devices.mac]?.state == .acceptedByProvider, sourceLocation: sourceLocation)
        #expect(byDevice[devices.phoneID]?.state == .capturedDryRun, sourceLocation: sourceLocation)
        #expect(byDevice[devices.padID]?.state == .capturedDryRun, sourceLocation: sourceLocation)
        let counts = try receipts(of: intent, devices, host: host, center: center)
        #expect(counts == [devices.mac: 1, devices.phoneID: 1, devices.padID: 1], sourceLocation: sourceLocation)
    }

    @Test("Reminders, important changes and brief availability reach every enabled device by default, once each")
    func everyEnabledDeviceByDefault() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let (testHost, host, devices, file) = try await openHost(
                scratch, at: "08:00", owner: owner(briefNotifications: true), center: center)
            let ownerClient = OwnerClient.inProcess(host)

            // 08:00: the 07:30 brief is ready and its availability is notified.
            await cycle(host, testHost, at: "08:00")
            let brief = try #require(try intents(.brief, in: host).first)
            try expectReachedEveryDevice(brief, devices, host: host, center: center)

            // 08:30: the reminder an hour before the task's deadline.
            let filing = try task("Synthetic tax filing", due: "09:30", on: host)
            await cycle(host, testHost, at: "08:30")
            let reminder = try reminderIntent(of: filing, in: host)
            #expect(reminder.category == .reminder)
            try expectReachedEveryDevice(reminder, devices, host: host, center: center)

            // 08:40: the 10:00 event moved to 10:30, an important change to a near confirmed commitment.
            try moveEvent(to: "10:30", "11:30", file: file, testHost)
            await cycle(host, testHost, at: "08:40")
            let change = try #require(try intents(.commitmentChange, in: host).first)
            #expect(try intents(.commitmentChange, in: host).count == 1)
            try expectReachedEveryDevice(change, devices, host: host, center: center)

            // A regenerated brief is a new version, but its availability is notified once per day by policy; later
            // cycles repeat nothing.
            let deliveriesBefore = try host.application.all(Delivery.self).count
            _ = try await ownerClient.regenerateBrief()
            await cycle(host, testHost, at: "08:50")
            #expect(try intents(.brief, in: host).count == 1)
            #expect(try host.application.all(Delivery.self).count == deliveriesBefore)
            for intent in [brief, reminder, change] {
                let counts = try receipts(of: intent, devices, host: host, center: center)
                #expect(counts == [devices.mac: 1, devices.phoneID: 1, devices.padID: 1])
            }
            #expect(try await ownerClient.health().deviceWarnings.isEmpty)
            host.close()
        }
    }

    @Test("A device that turns a category or all notifications off is skipped with a recorded reason")
    func perDevicePreferencesAreHonored() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let (testHost, host, devices, file) = try await openHost(
                scratch, at: "08:00", owner: owner(), center: center)
            let ownerClient = OwnerClient.inProcess(host)
            await cycle(host, testHost, at: "08:00")

            // The iPad turns off important changes; the iPhone turns its notifications off altogether.
            let padPreferences = try await devices.pad.client.notificationPreferences()
            let withoutChanges = padPreferences.categories.filter { $0 != "commitmentChange" }
            #expect(withoutChanges.count == NotificationCategory.allCases.count - 1)
            _ = try await devices.pad.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(
                    expectedRevision: padPreferences.revision, categories: withoutChanges))
            let phonePreferences = try await devices.phone.client.notificationPreferences()
            _ = try await devices.phone.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(expectedRevision: phonePreferences.revision, enabled: false))
            #expect(
                try await ownerClient.health().deviceWarnings == [
                    "Synthetic iPhone: notifications are turned off for this device"
                ])

            let filing = try task("Synthetic tax filing", due: "09:30", on: host)
            await cycle(host, testHost, at: "08:30")
            let reminder = try deliveries(of: try reminderIntent(of: filing, in: host), in: host)
            #expect(reminder[devices.mac]?.state == .acceptedByProvider)
            #expect(reminder[devices.padID]?.state == .capturedDryRun)
            #expect(reminder[devices.phoneID]?.state == .suppressed)
            #expect(reminder[devices.phoneID]?.stateReason == "notifications are turned off for this device")

            try moveEvent(to: "10:30", "11:30", file: file, testHost)
            await cycle(host, testHost, at: "08:40")
            let changed = try #require(try intents(.commitmentChange, in: host).first)
            let change = try deliveries(of: changed, in: host)
            #expect(change[devices.mac]?.state == .acceptedByProvider)
            #expect(change[devices.phoneID]?.stateReason == "notifications are turned off for this device")
            #expect(change[devices.padID]?.state == .suppressed)
            #expect(change[devices.padID]?.stateReason == "this category is turned off for this device")
            let captures = try host.recorder.recent(limit: 1_000).filter { $0.channel == .push }
            #expect(captures.count == 1)

            // The iPhone turns its notifications back on and receives the next one.
            let current = try await devices.phone.client.notificationPreferences()
            _ = try await devices.phone.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(expectedRevision: current.revision, enabled: true))
            #expect(try await ownerClient.health().deviceWarnings.isEmpty)
            let renewal = try task("Synthetic licence renewal", due: "09:35", on: host)
            await cycle(host, testHost, at: "08:45")
            let resumed = try deliveries(of: try reminderIntent(of: renewal, in: host), in: host)
            #expect(resumed[devices.phoneID]?.state == .capturedDryRun)
            #expect(resumed[devices.padID]?.state == .capturedDryRun)
            #expect(resumed[devices.mac]?.state == .acceptedByProvider)
            host.close()
        }
    }

    @Test("Reported permission denial is honored and recorded, even when reported between decision and send")
    func reportedDenialIsHonored() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let (testHost, host, devices, _) = try await openHost(scratch, at: "09:00", owner: owner(), center: center)
            let ownerClient = OwnerClient.inProcess(host)
            let denialReason = "the device reports notification permission as denied"

            let reported = try await devices.pad.client.reportNotificationStatus(
                NotificationStatusRequest(authorization: .denied, settings: ["alert": "disabled"]))
            #expect(!reported.canReceiveNotifications)
            #expect(reported.authorization == .denied)
            #expect(
                try await ownerClient.health().deviceWarnings == ["Synthetic iPad: notification permission is denied"])
            #expect(
                try host.application.all(AuditEvent.self).contains {
                    $0.action == "device.notification-permission" && $0.affected == [devices.padID.rawValue]
                        && $0.detail == "denied"
                })

            let first = try task("Synthetic first filing", due: "09:30", on: host)
            await cycle(host, testHost, at: "09:00")
            let denied = try deliveries(of: try reminderIntent(of: first, in: host), in: host)
            #expect(denied[devices.padID]?.state == .suppressed)
            #expect(denied[devices.padID]?.stateReason == denialReason)
            #expect(denied[devices.phoneID]?.state == .capturedDryRun)
            #expect(denied[devices.mac]?.state == .acceptedByProvider)

            // The iPhone reports denial after the next reminder was decided but before it was sent.
            testHost.clock.set(at("09:05"))
            let second = try task("Synthetic second filing", due: "09:45", on: host)
            #expect(try host.application.services.reminders.dispatchDue() == 1)
            let decided = try deliveries(of: try reminderIntent(of: second, in: host), in: host)
            #expect(decided[devices.phoneID]?.state == .pending)
            _ = try await devices.phone.client.reportNotificationStatus(
                NotificationStatusRequest(authorization: .denied))
            await host.runtime.runOnce()
            let sent = try deliveries(of: try reminderIntent(of: second, in: host), in: host)
            #expect(sent[devices.phoneID]?.state == .suppressed)
            #expect(sent[devices.phoneID]?.stateReason == denialReason)
            #expect(sent[devices.mac]?.state == .acceptedByProvider)
            #expect(try host.recorder.recent(limit: 1_000).filter { $0.channel == .push }.count == 1)

            // Both report notifications allowed again, and the next reminder reaches every device.
            for companion in [devices.phone, devices.pad] {
                _ = try await companion.client.reportNotificationStatus(
                    NotificationStatusRequest(authorization: .authorized))
            }
            #expect(try await ownerClient.health().deviceWarnings.isEmpty)
            let third = try task("Synthetic third filing", due: "10:00", on: host)
            await cycle(host, testHost, at: "09:10")
            try expectReachedEveryDevice(try reminderIntent(of: third, in: host), devices, host: host, center: center)
            host.close()
        }
    }

    @Test("Quiet hours defer every device's notification to their end, or let it expire, with the reason recorded")
    func quietHoursDeferOrExpire() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let (testHost, host, devices, _) = try await openHost(scratch, at: "06:20", owner: owner(), center: center)

            // Due 07:30: its reminder an hour before falls in quiet hours (22:00–07:00) and can wait until 07:00.
            // Due 06:55: its one reminder is due now and stops being valid before quiet hours end.
            let waiting = try task("Synthetic early train", due: "07:30", on: host)
            let expiring = try task("Synthetic dawn call", due: "06:55", on: host)
            await cycle(host, testHost, at: "06:30")
            let deferred = try deliveries(of: try reminderIntent(of: waiting, in: host), in: host)
            #expect(Set(deferred.keys) == devices.all)
            for delivery in deferred.values {
                #expect(delivery.state == .pending)
                #expect(delivery.stateReason == "deferred until quiet hours end")
                #expect(delivery.nextAttemptAt == at("07:00"))
                #expect(delivery.attempts.isEmpty)
            }
            let lapsed = try deliveries(of: try reminderIntent(of: expiring, in: host), in: host)
            #expect(Set(lapsed.keys) == devices.all)
            for delivery in lapsed.values {
                #expect(delivery.state == .cancelled)
                #expect(delivery.stateReason == "expired during quiet hours")
            }
            #expect(center.presented.isEmpty)
            #expect(try host.recorder.recent(limit: 1_000).filter { $0.channel == .push }.isEmpty)

            await cycle(host, testHost, at: "06:45")
            #expect(center.presented.isEmpty)
            await cycle(host, testHost, at: "07:00")
            try expectReachedEveryDevice(try reminderIntent(of: waiting, in: host), devices, host: host, center: center)
            await cycle(host, testHost, at: "07:05")
            let counts = try receipts(
                of: try reminderIntent(of: expiring, in: host), devices, host: host, center: center)
            #expect(counts.values.allSatisfy { $0 == 0 })
            #expect(center.presented.count == 1)
            host.close()
        }
    }
}
