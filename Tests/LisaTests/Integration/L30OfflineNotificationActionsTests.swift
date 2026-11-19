// Integration tests for L30, offline notification actions (NOTIFY-05, NOTIFY-07, UI-03, API-03; plan §6.5, §6.6):
// an action chosen on a delivered reminder notification while the host is unreachable, or too slow to answer within
// the submission time limit, is written to the companion's durable queue under its deterministic request ID
// (`na:<installation>:<notification>:<action>`), shown as pending, kept across a relaunch and a repeated system
// invocation, and applied once after reconnection: a snooze whose answer was lost is not applied a second time, and
// repeats after reconnection send nothing. An action that became stale while queued surfaces as a recoverable
// conflict and leaves the newer state alone. The same holds over loopback while the host is stopped and after it
// restarts. The payload is built by the real APNs payload builder from the host's own presentation; the Mac's
// notification center and the route to the host are test-only substitutes, and pushes are dry runs.

import Foundation
import LisaAPIContract
import LisaAPNs
import LisaClient
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L30 — Offline notification actions", .tags(.integration))
struct L30OfflineNotificationActionsTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Brief availability is not notified, so the task's reminder is the only notification; snoozing lasts 15 minutes.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        owner.reminders.snoozeMinutes = 15
        return owner
    }

    /// A delivered reminder: its task, its reminder and the payload a device receives for it.
    private struct Delivered {
        var task: LisaTask
        var reminder: Reminder
        var notificationID: String
        var payload: Data
    }

    /// Creates a confirmed task due at 09:30 and runs a cycle at 09:00, which delivers its reminder to every device.
    /// The payload is the APNs payload of the presentation the host made for the Mac.
    private func deliverReminder(
        _ host: LisaHost, center: ScriptedNotificationCenter, title: String = "Synthetic insurance renewal"
    ) async throws -> Delivered {
        let task = try host.application.createTask(
            TaskDraft(title: title, deadline: SyntheticTask.due(at("09:30"))), by: .localOwner)
        await host.runtime.runOnce()
        let presented = try #require(center.presented.first { $0.presentation.subjectID == task.id.rawValue })
        let reminder = try #require(try host.application.all(Reminder.self).first { $0.subject == .task(task.id) })
        #expect(reminder.state.name == "delivered")
        let payload = try APNsPayloadBuilder.payload(for: presented.presentation).json
        return Delivered(
            task: task, reminder: reminder, notificationID: presented.presentation.notificationID, payload: payload)
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

    @Test("An action taken while the host is unreachable is queued durably, shown as pending and applied once")
    func actionWhileUnreachableAppliedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let route = SwitchableTransport(.connected(host.deviceTransport))
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let delivered = try await deliverReminder(host, center: center)
            route.set(.unreachable)

            // Opening the notification shows its item and queues nothing.
            let opened = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationResponseAction.openIdentifier,
                timeLimit: .seconds(5))
            #expect(opened.opensItem)
            #expect(opened.entry == nil)
            #expect(opened.subject.subjectID == delivered.task.id.rawValue)
            #expect(await phone.queue.allEntries.isEmpty)

            let outcome = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.complete.rawValue,
                timeLimit: .seconds(10))
            let entry = try #require(outcome.entry)
            let installation = try await phone.installationID()
            #expect(entry.id == "na:\(installation):\(delivered.notificationID):LISA_COMPLETE")
            #expect(entry.kind == .notificationAction)
            #expect(entry.status == .pending)
            #expect(entry.lastError?.message.contains("could not be reached") == true)
            #expect(await phone.queue.pendingEntries.map(\.id) == [entry.id])
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "delivered")
            #expect(try host.application.record(LisaTask.self, id: delivered.task.id)?.status == .open)

            // The system invokes the handler again for the same response, and the app is relaunched: one entry.
            let repeated = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.complete.rawValue,
                timeLimit: .seconds(10))
            #expect(repeated.entry?.id == entry.id)
            try phone.relaunch()
            #expect(await phone.queue.allEntries.map(\.id) == [entry.id])
            #expect(await phone.queue.pendingEntries.first?.requestID == entry.requestID)

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [entry.id])
            #expect(report.remaining == 0)
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "completed")
            #expect(try host.application.record(LisaTask.self, id: delivered.task.id)?.status == .completed)
            #expect(try applications("complete", of: delivered.reminder.id, in: host) == 1)
            let done = try #require(await phone.queue.entry(entry.id))
            #expect(done.status == .done)
            let result = try #require(try done.decodedResponse(as: NotificationActionResult.self))
            #expect(result.notificationID == delivered.notificationID)
            #expect(result.reminder?.state == "completed")

            // Repeats after reconnection send nothing.
            let exchanged = route.exchanges.count
            _ = await phone.queue.flush(using: phone.client)
            let again = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.complete.rawValue,
                timeLimit: .seconds(10))
            #expect(again.entry?.status == .done)
            #expect(route.exchanges.count == exchanged)
            #expect(try applications("complete", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("A snooze whose answer was lost is resent with its request ID and applied once")
    func lostSnoozeAppliedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: route, clock: testHost.clock)
            try await pad.pair(codeFrom: OwnerClient.inProcess(host))
            let delivered = try await deliverReminder(host, center: center)

            route.set(.losingAnswers(host.deviceTransport))
            let outcome = try await pad.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.snooze.rawValue,
                timeLimit: .seconds(10))
            let entry = try #require(outcome.entry)
            #expect(entry.status == .pending)
            #expect(entry.uncertainSince == at("09:00"))
            #expect(try reminderState(delivered.reminder.id, in: host) == .snoozed(until: at("09:15")))

            // Two minutes later the pad reconnects; snoozing again then would move the reminder to 09:17.
            testHost.advance(minutes: 2)
            route.set(.connected(host.deviceTransport))
            let report = await pad.queue.flush(using: pad.client)
            #expect(report.applied == [entry.id])
            let retry = try #require(route.exchanges.last)
            #expect(retry.request.header("Lisa-Request-ID") == entry.requestID)
            #expect(APIExchange.isReplay(retry.response))
            #expect(try reminderState(delivered.reminder.id, in: host) == .snoozed(until: at("09:15")))
            #expect(try applications("snooze", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("An action the host is too slow to accept in time stays pending and is applied once later")
    func actionWhileHostTooSlowStaysPending() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let delivered = try await deliverReminder(host, center: center)

            route.set(.stalled)
            let began = ContinuousClock.now
            let outcome = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.acknowledge.rawValue,
                timeLimit: .milliseconds(200))
            #expect(ContinuousClock.now - began < .seconds(30))
            let entry = try #require(outcome.entry)
            #expect(entry.status == .pending)
            #expect(await phone.queue.pendingEntries.map(\.id) == [entry.id])
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "delivered")

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [entry.id])
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "acknowledged")
            // Acknowledging never completes the task.
            #expect(try host.application.record(LisaTask.self, id: delivered.task.id)?.status == .open)
            #expect(try applications("acknowledge", of: delivered.reminder.id, in: host) == 1)
            host.close()
        }
    }

    @Test("An action that became stale while queued surfaces as a recoverable conflict and leaves the newer state")
    func staleQueuedActionSurfacesConflict() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let owner = OwnerClient.inProcess(host)
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            let delivered = try await deliverReminder(host, center: center)

            route.set(.unreachable)
            let outcome = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.snooze.rawValue,
                timeLimit: .seconds(10))
            let entry = try #require(outcome.entry)
            #expect(entry.status == .pending)

            // Meanwhile the owner completes the task on the host, which ends its reminder.
            testHost.advance(minutes: 3)
            let current = try await owner.task(id: delivered.task.id.rawValue)
            _ = try await owner.updateTask(
                id: delivered.task.id.rawValue,
                TaskPatchRequest(expectedRevision: current.revision, status: .completed))
            let ended = try #require(try reminderState(delivered.reminder.id, in: host))
            #expect(ended.isTerminal)

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.conflicts == [entry.id])
            #expect(report.applied.isEmpty)
            let conflict = try #require(await phone.queue.entry(entry.id))
            #expect(conflict.status == .conflict)
            #expect(conflict.lastError?.status == 409)
            #expect(conflict.lastError?.code == .conflict)
            #expect(await phone.queue.conflictEntries.map(\.id) == [entry.id])
            #expect(await phone.queue.pendingEntries.isEmpty)
            #expect(try reminderState(delivered.reminder.id, in: host) == ended)
            #expect(try host.application.record(LisaTask.self, id: delivered.task.id)?.status == .completed)
            #expect(try applications("snooze", of: delivered.reminder.id, in: host) == 0)

            // The conflict is recoverable: the owner dismisses the stale action.
            try await phone.queue.discard(entry.id)
            #expect(await phone.queue.allEntries.isEmpty)
            host.close()
        }
    }

    @Test("Over loopback, an action taken while the host is stopped is applied once after the host restarts")
    func actionWhileHostStoppedOverLoopback() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            testHost.settings.api = LoopbackAPIServer.settings()
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            var server = try await LoopbackAPIServer.start(for: host)
            let transport = try server.deviceTransport()
            defer { transport.invalidate() }
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: transport, clock: testHost.clock)
            try await phone.pair(codeFrom: server.ownerClient())
            let delivered = try await deliverReminder(host, center: center)

            // The host stops; the action is chosen while nothing answers on the device port.
            await server.stop()
            host.close()
            let outcome = try await phone.notificationActions.handle(
                payloadJSON: delivered.payload, actionIdentifier: NotificationActionID.acknowledge.rawValue,
                timeLimit: .seconds(20))
            let entry = try #require(outcome.entry)
            #expect(entry.status == .pending)
            try phone.relaunch()
            #expect(await phone.queue.pendingEntries.map(\.id) == [entry.id])

            testHost.advance(minutes: 5)
            testHost.settings.api = LoopbackAPIServer.settings(port: server.devicePort)
            host = try testHost.open()
            server = try await LoopbackAPIServer.start(for: host)
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "delivered")
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [entry.id])
            #expect(try reminderState(delivered.reminder.id, in: host)?.name == "acknowledged")
            #expect(try applications("acknowledge", of: delivered.reminder.id, in: host) == 1)
            _ = await phone.queue.flush(using: phone.client)
            #expect(try applications("acknowledge", of: delivered.reminder.id, in: host) == 1)
            await server.stop()
            host.close()
        }
    }
}
