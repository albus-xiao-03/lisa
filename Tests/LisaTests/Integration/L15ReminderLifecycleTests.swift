// Integration tests for L15, the reminder lifecycle (REM-01, REM-02, REM-03, NOTIFY-03; D-16, D-26, D-27): one
// reminder per configured offset, and one reminder rather than a burst for a commitment found late; completion cancels
// reminders and suppresses pending deliveries on every device; snooze fires again as a new occurrence; dismissal ends a
// reminder; acknowledgement never completes the task; completing from a reminder completes the task; a deadline change
// replaces obsolete reminders; a date-only deadline is reminded only at a configured time.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("L15 — Reminder lifecycle", .tags(.integration))
struct L15ReminderLifecycleTests {
    private func at(_ iso: String) -> Date {
        TestTime.instant(iso, in: TestTime.newYork)
    }

    /// Moves the clock to `iso` in New York and runs one host cycle, as the runtime does every few minutes.
    private func cycle(_ host: LisaHost, _ testHost: TestHost, at iso: String) async {
        testHost.clock.set(at(iso))
        await host.runtime.runOnce()
    }

    /// The task's reminders, earliest first.
    private func reminders(of task: TaskID, in host: LisaHost) throws -> [Reminder] {
        try host.application.all(Reminder.self).filter { $0.subject == .task(task) }.sorted { $0.dueAt < $1.dueAt }
    }

    /// The notification occurrences recorded for `reminder`.
    private func occurrences(of reminder: ReminderID, in host: LisaHost) throws -> [NotificationIntent] {
        try host.application.all(NotificationIntent.self).filter { $0.subject == .reminder(reminder) }
    }

    /// How many times the center was asked to present an occurrence of `reminder`.
    private func presentations(
        of reminder: ReminderID, in host: LisaHost, center: ScriptedNotificationCenter
    ) throws -> Int {
        let ids = Set(try occurrences(of: reminder, in: host).map(\.id.rawValue))
        return center.presented.filter { ids.contains($0.presentation.notificationID) }.count
    }

    @Test("Each configured offset fires one reminder for a deadline; no second reminder joins the last one")
    func oneReminderPerOffset() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T08:00"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Submit the synthetic filing", deadline: SyntheticTask.due(at("2026-11-17T10:00"))),
                by: .localOwner)
            // Cycles every five minutes around each reminder time: 24 hours and 1 hour before the deadline.
            for time in [
                "2026-11-16T09:55", "2026-11-16T10:00", "2026-11-16T10:05", "2026-11-17T08:55", "2026-11-17T09:00",
                "2026-11-17T09:05",
            ] {
                await cycle(host, testHost, at: time)
            }
            let stored = try reminders(of: task.id, in: host)
            #expect(
                stored.map(\.dueAt) == [at("2026-11-16T10:00"), at("2026-11-17T09:00")],
                "reminders: \(stored.map(\.occurrenceKey))")
            #expect(stored.allSatisfy { $0.state.name == "delivered" })
            #expect(center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.count == 2)
            host.close()
        }
    }

    @Test("A commitment found after every offset passed gets one reminder now, not every reminder it missed")
    func lateCommitmentGetsOneReminder() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T09:30"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Sign the synthetic form", deadline: SyntheticTask.due(at("2026-11-16T10:00"))),
                by: .localOwner)
            for time in ["2026-11-16T09:30", "2026-11-16T09:35", "2026-11-16T09:40"] {
                await cycle(host, testHost, at: time)
            }
            let stored = try reminders(of: task.id, in: host)
            #expect(stored.count == 1)
            #expect(stored.first?.dueAt == at("2026-11-16T09:30"))
            #expect(center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.count == 1)
            host.close()
        }
    }

    @Test("Completing a task cancels its reminders and suppresses their pending deliveries on every device")
    func completionCancelsAndSuppresses() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            // 05:50 is inside the default quiet hours (22:00–07:00), so the 06:30 reminder waits for 07:00.
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T05:50"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            try TestHost.pairPhone(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Mail the synthetic forms", deadline: SyntheticTask.due(at("2026-11-16T07:30"))),
                by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T06:30")
            let fired = try reminders(of: task.id, in: host).filter { $0.state.name == "delivered" }
            #expect(!fired.isEmpty)
            let payloads = Set(try fired.flatMap { try occurrences(of: $0.id, in: host) }.map(\.id.rawValue))
            let deliveries = {
                try host.application.all(Delivery.self).filter { delivery in
                    if case .notification(let id) = delivery.payload { return payloads.contains(id.rawValue) }
                    return false
                }
            }
            // One delivery per device and occurrence, held until quiet hours end.
            #expect(try deliveries().count == 2 * payloads.count)
            #expect(try deliveries().allSatisfy { $0.state == .pending && $0.nextAttemptAt == at("2026-11-16T07:00") })

            testHost.clock.set(at("2026-11-16T06:40"))
            _ = try host.application.setTaskStatus(task.id, to: .completed, expectedRevision: nil, by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T07:05")
            #expect(try deliveries().allSatisfy { $0.state == .suppressed })
            #expect(try deliveries().allSatisfy { $0.stateReason?.contains("completed") == true })
            #expect(try reminders(of: task.id, in: host).allSatisfy { $0.state.name == "cancelled" })
            #expect(center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.isEmpty)
            host.close()
        }
    }

    @Test("Snoozing fires the reminder again as a new occurrence after the snooze; dismissing ends it")
    func snoozeAndDismissal() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T08:00"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Confirm the synthetic booking", deadline: SyntheticTask.due(at("2026-11-16T11:00"))),
                by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T10:00")
            let reminder = try #require(
                try reminders(of: task.id, in: host).first { $0.occurrenceKey.hasSuffix(":60") })
            #expect(reminder.state.name == "delivered")
            #expect(try presentations(of: reminder.id, in: host, center: center) == 1)

            testHost.clock.set(at("2026-11-16T10:01"))
            let snoozed = try host.application.actOnReminder(
                .snooze, reminder.id, expectedRevision: nil, by: .localOwner)
            #expect(snoozed.state == .snoozed(until: at("2026-11-16T10:16")))
            await cycle(host, testHost, at: "2026-11-16T10:10")
            #expect(try presentations(of: reminder.id, in: host, center: center) == 1)
            await cycle(host, testHost, at: "2026-11-16T10:16")
            #expect(try presentations(of: reminder.id, in: host, center: center) == 2)
            // The repeat is its own notification occurrence, so it is delivered again rather than deduplicated away.
            #expect(try occurrences(of: reminder.id, in: host).count == 2)

            testHost.clock.set(at("2026-11-16T10:17"))
            _ = try host.application.actOnReminder(.dismiss, reminder.id, expectedRevision: nil, by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T10:35")
            await cycle(host, testHost, at: "2026-11-16T10:50")
            #expect(try presentations(of: reminder.id, in: host, center: center) == 2)
            #expect(try host.application.record(Reminder.self, id: reminder.id)?.state.name == "dismissed")
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .open)
            host.close()
        }
    }

    @Test("Acknowledging from a device ends that reminder but never completes the task; later reminders still fire")
    func acknowledgementKeepsTheTaskOpen() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            var owner = TestHost.owner()
            owner.reminders.deadlineOffsetsMinutes = [120, 60]
            let testHost = TestHost(
                scratch: scratch, now: at("2026-11-16T08:00"), owner: owner, localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let phone = try TestHost.pairPhone(on: host)
            let task = try host.application.createTask(
                TaskDraft(
                    title: "Review the synthetic draft", priority: .high,
                    deadline: SyntheticTask.due(at("2026-11-16T12:00"))),
                by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T10:00")
            let early = try #require(try reminders(of: task.id, in: host).first { $0.occurrenceKey.hasSuffix(":120") })
            let notification = try #require(try occurrences(of: early.id, in: host).first)
            testHost.clock.set(at("2026-11-16T10:05"))
            try host.application.actOnNotification(
                .acknowledge, notificationID: notification.id, by: .pairedDevice(phone))
            #expect(try host.application.record(Reminder.self, id: early.id)?.state.name == "acknowledged")
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .open)

            await cycle(host, testHost, at: "2026-11-16T11:00")
            let later = try #require(try reminders(of: task.id, in: host).first { $0.occurrenceKey.hasSuffix(":60") })
            #expect(later.state.name == "delivered")
            #expect(try presentations(of: later.id, in: host, center: center) == 1)
            #expect(try presentations(of: early.id, in: host, center: center) == 1)
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .open)
            host.close()
        }
    }

    @Test("Completing from a reminder completes its task and cancels the task's other reminders")
    func completingFromAReminder() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T08:00"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Pay the synthetic invoice", deadline: SyntheticTask.due(at("2026-11-17T11:00"))),
                by: .localOwner)
            await cycle(host, testHost, at: "2026-11-16T11:00")
            let first = try #require(try reminders(of: task.id, in: host).first { $0.state.name == "delivered" })
            _ = try host.application.actOnReminder(.complete, first.id, expectedRevision: nil, by: .localOwner)
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .completed)
            let after = try reminders(of: task.id, in: host)
            #expect(after.first { $0.id == first.id }?.state.name == "completed")
            #expect(after.filter { $0.id != first.id }.allSatisfy { $0.state.name == "cancelled" })
            await cycle(host, testHost, at: "2026-11-17T10:00")
            #expect(center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.count == 1)
            host.close()
        }
    }

    @Test("A deadline change cancels the obsolete reminders and schedules ones for the new deadline")
    func deadlineChangeReplacesReminders() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T08:00"), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "File the synthetic claim", deadline: SyntheticTask.due(at("2026-11-17T15:00"))),
                by: .localOwner)
            let original = try reminders(of: task.id, in: host)
            #expect(original.map(\.dueAt) == [at("2026-11-16T15:00"), at("2026-11-17T14:00")])

            testHost.clock.set(at("2026-11-16T09:00"))
            _ = try host.application.correctTask(
                task.id,
                expectedRevision: try #require(try host.application.record(LisaTask.self, id: task.id)).revision,
                TaskCorrection(deadline: SyntheticTask.due(at("2026-11-18T15:00"))), by: .localOwner)
            let replaced = try reminders(of: task.id, in: host)
            let old = replaced.filter { reminder in original.contains { $0.id == reminder.id } }
            let new = replaced.filter { reminder in !original.contains { $0.id == reminder.id } }
            #expect(old.allSatisfy { $0.state == .cancelled(reason: "the task changed") })
            #expect(new.map(\.dueAt) == [at("2026-11-17T15:00"), at("2026-11-18T14:00")])
            #expect(new.allSatisfy { $0.state == .scheduled })

            for time in ["2026-11-16T15:00", "2026-11-17T14:00", "2026-11-17T15:00"] {
                await cycle(host, testHost, at: time)
            }
            for reminder in old { #expect(try presentations(of: reminder.id, in: host, center: center) == 0) }
            let firstNew = try #require(new.first)
            #expect(try presentations(of: firstNew.id, in: host, center: center) == 1)
            host.close()
        }
    }

    @Test("A date-only deadline gets a reminder only at a configured time, and keeps its date-only meaning")
    func dateOnlyDeadlineNeedsAConfiguredTime() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            var testHost = TestHost(scratch: scratch, now: at("2026-11-16T08:00"), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(title: "Renew the synthetic permit", deadline: .onDate(TestTime.date("2026-11-18"))),
                by: .localOwner)
            #expect(try reminders(of: task.id, in: host).isEmpty)

            testHost.settings.ownerSettings.reminders.dateOnlyReminderTime = TestTime.time("09:00")
            try testHost.restart(&host)
            await cycle(host, testHost, at: "2026-11-16T08:05")
            let stored = try reminders(of: task.id, in: host)
            #expect(stored.map(\.rule) == [.dateOnlyDeadline])
            #expect(stored.map(\.dueAt) == [at("2026-11-18T09:00")])
            #expect(
                try host.application.record(LisaTask.self, id: task.id)?.deadline
                    == .onDate(TestTime.date("2026-11-18")))
            await cycle(host, testHost, at: "2026-11-18T09:00")
            #expect(center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.count == 1)
            host.close()
        }
    }
}
