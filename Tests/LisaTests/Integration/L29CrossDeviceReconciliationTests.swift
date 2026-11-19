// Integration tests for L29, cross-device reconciliation (NOTIFY-01, NOTIFY-03, NOTIFY-05, REM-01, API-03; plan §6.1,
// §6.4, §6.5; D-26, D-27), through the real host in process and over loopback: when one device acknowledges, snoozes
// or completes a delivered reminder, the host suppresses the obsolete delivery still pending for another device and
// recomputes the reminders that follow — an acknowledgement stops only that reminder, a snooze makes the host fire it
// again for every device, and a completion cancels the task's later reminders. The other devices find the current
// state when they next connect. An action another device queued while offline, made stale by the first device's
// action, is a recoverable conflict that changes nothing. Devices act through their notification handlers with the
// payload the real APNs payload builder makes from the host's presentation; the Mac's notification center and the
// routes to the host are test-only substitutes, and pushes are dry runs.

import Foundation
import LisaAPIContract
import LisaAPNs
import LisaClient
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L29 — Cross-device reconciliation", .tags(.integration))
struct L29CrossDeviceReconciliationTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Reminders an hour and half an hour before a deadline; a snooze lasts 15 minutes; brief availability is not
    /// notified, so the task's reminders are the only notifications.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.reminders.deadlineOffsetsMinutes = [60, 30]
        owner.reminders.snoozeMinutes = 15
        owner.notifications.notifyBriefAvailability = false
        return owner
    }

    /// The Mac's busy notification center fails its first presentation, which then waits for a retry.
    private func busyCenter() -> ScriptedNotificationCenter {
        ScriptedNotificationCenter(steps: [
            .answer(.temporarilyUnavailable(reason: "the synthetic notification center is busy", retryAfter: nil))
        ])
    }

    /// The Mac's installation, a paired iPhone and iPad, and a confirmed task due at 10:00 whose reminders fire at
    /// 09:00 and 09:30.
    private struct Scenario {
        var testHost: TestHost
        var host: LisaHost
        var mac: DeviceID
        var phone: SyntheticCompanion
        var pad: SyntheticCompanion
        var phoneID: DeviceID
        var padID: DeviceID
        var task: LisaTask

    }

    /// The first reminder as delivered: its reminder, its notification and the payload the devices received.
    private struct Delivered {
        var reminder: Reminder
        var intent: NotificationIntent
        var payload: Data
    }

    /// Registers the Mac, pairs the companions over their routes with a code from `ownerClient`, and creates the task.
    private func scenario(
        _ scratch: ScratchDirectory, _ testHost: TestHost, _ host: LisaHost, owner ownerClient: LisaAPIClient,
        phoneRoute: any APITransport, padRoute: any APITransport
    ) async throws -> Scenario {
        let mac = try TestHost.registerMac(on: host)
        let phone = try SyntheticCompanion(
            "Synthetic iPhone", in: scratch, transport: phoneRoute, clock: testHost.clock)
        let pad = try SyntheticCompanion(
            "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: padRoute, clock: testHost.clock)
        let phoneID = DeviceID(try await phone.pair(codeFrom: ownerClient))
        let padID = DeviceID(try await pad.pair(codeFrom: ownerClient))
        let task = try host.application.createTask(
            TaskDraft(title: "Synthetic grant report", deadline: SyntheticTask.due(at("10:00"))), by: .localOwner)
        return Scenario(
            testHost: testHost, host: host, mac: mac, phone: phone, pad: pad, phoneID: phoneID, padID: padID,
            task: task)
    }

    /// The same scenario with both companions in process, on the host's device transport.
    private func inProcess(_ scratch: ScratchDirectory, center: ScriptedNotificationCenter) async throws -> Scenario {
        let testHost = TestHost(scratch: scratch, now: at("08:55"), owner: owner(), localNotifications: center)
        let host = try testHost.open()
        return try await scenario(
            scratch, testHost, host, owner: OwnerClient.inProcess(host), phoneRoute: host.deviceTransport,
            padRoute: host.deviceTransport)
    }

    private func cycle(_ scenario: Scenario, at time: String) async {
        scenario.testHost.clock.set(at(time))
        await scenario.host.runtime.runOnce()
    }

    /// Runs the 09:00 cycle, which fires the first reminder for every device.
    private func deliverFirstReminder(
        _ scenario: Scenario, center: ScriptedNotificationCenter
    ) async throws -> Delivered {
        await cycle(scenario, at: "09:00")
        let intents = try TaskNotifications.occurrences(of: scenario.task.id, in: scenario.host)
        #expect(intents.count == 1)
        let intent = try #require(intents.first)
        let reminder = try #require(
            try scenario.host.application.all(Reminder.self).first { intent.subject == .reminder($0.id) })
        let presented = try #require(center.presented.first { $0.presentation.notificationID == intent.id.rawValue })
        let payload = try APNsPayloadBuilder.payload(for: presented.presentation).json
        return Delivered(reminder: reminder, intent: intent, payload: payload)
    }

    private func delivery(of intent: NotificationIntent, to device: DeviceID, in host: LisaHost) throws -> Delivery? {
        try host.application.all(Delivery.self).first {
            $0.payload == .notification(intent.id) && $0.recipient == .device(device)
        }
    }

    private func reminderState(_ id: ReminderID, in host: LisaHost) throws -> ReminderState? {
        try host.application.record(Reminder.self, id: id)?.state
    }

    /// How many times the host applied `action` to the reminder.
    private func applications(_ action: String, of id: ReminderID, in host: LisaHost) throws -> Int {
        try host.application.all(AuditEvent.self).filter {
            $0.action == "reminder.\(action)" && $0.affected.contains(id.rawValue)
        }.count
    }

    /// The reminder notifications of the task other than `first`.
    private func later(than first: NotificationIntent, _ scenario: Scenario) throws -> [NotificationIntent] {
        try TaskNotifications.occurrences(of: scenario.task.id, in: scenario.host).filter { $0.id != first.id }
    }

    @Test("An acknowledgement from one device suppresses another's pending delivery and stops only that reminder")
    func acknowledgementReconcilesEveryDevice() async throws {
        try await ScratchDirectory.with { scratch in
            let center = busyCenter()
            let scenario = try await inProcess(scratch, center: center)
            let host = scenario.host
            let delivered = try await deliverFirstReminder(scenario, center: center)
            #expect(try delivery(of: delivered.intent, to: scenario.mac, in: host)?.state == .pending)
            #expect(try delivery(of: delivered.intent, to: scenario.phoneID, in: host)?.state == .capturedDryRun)
            #expect(try delivery(of: delivered.intent, to: scenario.padID, in: host)?.state == .capturedDryRun)

            let outcome = try await scenario.phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.acknowledge.rawValue,
                timeLimit: .seconds(10))
            #expect(outcome.entry?.status == .done)
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "acknowledged")
            let obsolete = try #require(try delivery(of: delivered.intent, to: scenario.mac, in: host))
            #expect(obsolete.state == .suppressed)
            #expect(obsolete.stateReason == "acknowledged")
            // Acknowledging never completes the task.
            #expect(try host.application.record(LisaTask.self, id: scenario.task.id)?.status == .open)

            // The Mac's retry time passes and nothing more is presented there.
            await cycle(scenario, at: "09:05")
            #expect(TaskNotifications.presentations(of: scenario.task.id, center: center) == 1)
            // The iPad sees the acknowledgement when it next connects.
            let seen = try await scenario.pad.client.reminders(states: ["acknowledged"]).items
            #expect(seen.map(\.id) == [delivered.reminder.id.rawValue])

            // The later reminder still reaches every device.
            await cycle(scenario, at: "09:30")
            let next = try #require(try later(than: delivered.intent, scenario).first)
            #expect(try later(than: delivered.intent, scenario).count == 1)
            #expect(try delivery(of: next, to: scenario.mac, in: host)?.state == .acceptedByProvider)
            #expect(try delivery(of: next, to: scenario.phoneID, in: host)?.state == .capturedDryRun)
            #expect(try delivery(of: next, to: scenario.padID, in: host)?.state == .capturedDryRun)
            #expect(try applications("acknowledge", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("Completing the task from one device suppresses another's pending delivery and cancels later reminders")
    func completionReconcilesEveryDevice() async throws {
        try await ScratchDirectory.with { scratch in
            let center = busyCenter()
            let scenario = try await inProcess(scratch, center: center)
            let host = scenario.host
            let delivered = try await deliverFirstReminder(scenario, center: center)
            let scheduled = try host.application.all(Reminder.self).filter {
                $0.subject == .task(scenario.task.id) && $0.id != delivered.reminder.id
            }
            #expect(scheduled.map(\.state) == [.scheduled])

            let outcome = try await scenario.pad.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.complete.rawValue,
                timeLimit: .seconds(10))
            #expect(outcome.entry?.status == .done)
            #expect(try host.application.record(LisaTask.self, id: scenario.task.id)?.status == .completed)
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "completed")
            #expect(try delivery(of: delivered.intent, to: scenario.mac, in: host)?.state == .suppressed)
            let second = try #require(scheduled.first)
            #expect(try reminderState(second.id, in: host) == .cancelled(reason: "the task was completed"))

            // Nothing more is sent for the task, on any device.
            let deliveriesAfter = try TaskNotifications.deliveries(of: scenario.task.id, in: host).count
            await cycle(scenario, at: "09:05")
            await cycle(scenario, at: "09:30")
            #expect(try later(than: delivered.intent, scenario).isEmpty)
            #expect(try TaskNotifications.deliveries(of: scenario.task.id, in: host).count == deliveriesAfter)
            #expect(TaskNotifications.presentations(of: scenario.task.id, center: center) == 1)
            #expect(try host.recorder.recent(limit: 1_000).filter { $0.channel == .push }.count == 2)

            // The iPhone finds the task complete and its reminders closed when it next connects.
            #expect(try await scenario.phone.client.task(id: scenario.task.id.rawValue).status == .completed)
            let closed = try await scenario.phone.client.reminders(states: ["completed", "cancelled"]).items
            #expect(Set(closed.map(\.id)) == Set(([delivered.reminder] + scheduled).map(\.id.rawValue)))
            #expect(try applications("complete", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("A snooze from one device suppresses another's pending delivery and the host fires it again for every device")
    func snoozeReconcilesEveryDevice() async throws {
        try await ScratchDirectory.with { scratch in
            let center = busyCenter()
            let scenario = try await inProcess(scratch, center: center)
            let host = scenario.host
            let delivered = try await deliverFirstReminder(scenario, center: center)

            let outcome = try await scenario.phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.snooze.rawValue,
                timeLimit: .seconds(10))
            #expect(outcome.entry?.status == .done)
            #expect(try reminderState(delivered.reminder.id, in: host) == .snoozed(until: at("09:15")))
            let obsolete = try #require(try delivery(of: delivered.intent, to: scenario.mac, in: host))
            #expect(obsolete.state == .suppressed)
            #expect(obsolete.stateReason == "snoozed")

            await cycle(scenario, at: "09:05")
            #expect(try later(than: delivered.intent, scenario).isEmpty)
            // At 09:15 the host fires the snoozed reminder again, as a new notification for every device.
            await cycle(scenario, at: "09:15")
            let again = try later(than: delivered.intent, scenario)
            #expect(again.count == 1)
            let repeated = try #require(again.first)
            #expect(repeated.subject == .reminder(delivered.reminder.id))
            #expect(try delivery(of: repeated, to: scenario.mac, in: host)?.state == .acceptedByProvider)
            #expect(try delivery(of: repeated, to: scenario.phoneID, in: host)?.state == .capturedDryRun)
            #expect(try delivery(of: repeated, to: scenario.padID, in: host)?.state == .capturedDryRun)
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "delivered")
            #expect(try applications("snooze", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("Over loopback, an action another device queued offline and made stale is a recoverable conflict")
    func staleActionFromAnotherDeviceConflicts() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            var testHost = TestHost(scratch: scratch, now: at("08:55"), owner: owner(), localNotifications: center)
            testHost.settings.api = LoopbackAPIServer.settings()
            let host = try testHost.open()
            let server = try await LoopbackAPIServer.start(for: host)
            let phoneTransport = try server.deviceTransport()
            let padTransport = try server.deviceTransport()
            defer {
                phoneTransport.invalidate()
                padTransport.invalidate()
            }
            let padRoute = SwitchableTransport(.connected(padTransport))
            let scenario = try await scenario(
                scratch, testHost, host, owner: try server.ownerClient(), phoneRoute: phoneTransport,
                padRoute: padRoute)
            let delivered = try await deliverFirstReminder(scenario, center: center)

            // The iPad has no route to the host when the owner snoozes the reminder there.
            padRoute.set(.unreachable)
            let queued = try await scenario.pad.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.snooze.rawValue,
                timeLimit: .seconds(5))
            let entry = try #require(queued.entry)
            #expect(entry.status == .pending)
            // Meanwhile the iPhone acknowledges the same notification over the network.
            let acknowledged = try await scenario.phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.acknowledge.rawValue,
                timeLimit: .seconds(20))
            #expect(acknowledged.entry?.status == .done)
            let current = try #require(try reminderState(delivered.reminder.id, in: host))
            #expect(current.name == "acknowledged")

            // When the iPad reconnects, its snooze is stale: a recoverable conflict that leaves the newer state alone.
            padRoute.set(.connected(padTransport))
            let report = await scenario.pad.queue.flush(using: scenario.pad.client)
            #expect(report.conflicts == [entry.id])
            #expect(report.applied.isEmpty)
            let conflict = try #require(await scenario.pad.queue.entry(entry.id))
            #expect(conflict.status == .conflict)
            #expect(conflict.lastError?.status == 409)
            #expect(conflict.lastError?.code == .conflict)
            #expect(try reminderState(delivered.reminder.id, in: host) == current)
            #expect(try applications("snooze", of: delivered.reminder.id, in: host) == 0)
            #expect(try applications("acknowledge", of: delivered.reminder.id, in: host) == 1)

            // The owner dismisses the stale action on the iPad, which shows the current state.
            try await scenario.pad.queue.discard(entry.id)
            #expect(await scenario.pad.queue.allEntries.isEmpty)
            let seen = try await scenario.pad.client.reminders(states: ["acknowledged"]).items
            #expect(seen.map(\.id) == [delivered.reminder.id.rawValue])
            await server.stop()
            host.close()
        }
    }
}
