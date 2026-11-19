// Recovery tests for §16.3, host downtime spanning several reminder times, with the reminder recovery policy (REM-04,
// REM-02, BRIEF-03; D-16, D-27, D-36): when the host reopens, reminders whose deadline passed give way to one overdue
// reminder, missed low-priority follow-ups are coalesced, no proposal gets more than one follow-up that day, every
// skip is recorded with its reason, and at most one catch-up brief is sent within the window while a later one is
// recorded as skipped.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("§16.3 — Host downtime spanning several reminder times", .tags(.recovery))
struct HostDowntimeRecoveryTests {
    private func at(_ iso: String) -> Date {
        TestTime.instant(iso, in: TestTime.newYork)
    }

    @Test("Missed reminders are reconciled once: one overdue reminder, coalesced follow-ups, every skip recorded")
    func missedRemindersAreReconciled() async throws {
        try await ScratchDirectory.with { scratch in
            let mailbox = scratch.path("mailbox")
            for (index, day) in ["2026-11-20", "2026-11-21"].enumerated() {
                try SourceFiles.write(
                    SyntheticInvitation.mail(
                        SyntheticEvent(
                            uid: "downtime-\(index)@example.com", title: "Synthetic workshop \(index + 1)",
                            start: "\(day)T14:00", end: "\(day)T15:00"),
                        messageID: "<downtime-\(index)@example.com>"),
                    named: "m00\(index)", in: mailbox, receivedAt: at("2026-11-16T07:00"))
            }
            let center = ScriptedNotificationCenter()
            var owner = TestHost.owner()
            owner.notifications.notifyBriefAvailability = false
            let testHost = TestHost(
                scratch: scratch, now: at("2026-11-16T08:00"), owner: owner, sources: [SourceFiles.mailSource(mailbox)],
                localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            // Due Tuesday 09:00: reminders on Monday at 09:00 and Tuesday at 08:00.
            let permit = try host.application.createTask(
                TaskDraft(title: "Synthetic permit renewal", deadline: SyntheticTask.due(at("2026-11-17T09:00"))),
                by: .localOwner)
            await host.runtime.runOnce()
            let proposals = try host.application.all(EventProposal.self)
            #expect(proposals.count == 2)
            let missed = try host.application.all(Reminder.self).filter { $0.state == .scheduled }
            #expect(missed.count == 4)

            // The host is off from Monday 08:05 until Tuesday 11:00, across all four reminder times.
            testHost.clock.set(at("2026-11-16T08:05"))
            host.close()
            testHost.clock.set(at("2026-11-17T11:00"))
            host = try testHost.open()

            let suppressed = try host.application.all(Reminder.self).filter { $0.state.name == "suppressed" }
            #expect(suppressed.count == 3)
            let deadlineSkips = suppressed.filter { $0.subject == .task(permit.id) }
            #expect(deadlineSkips.count == 2)
            #expect(
                deadlineSkips.allSatisfy {
                    $0.state
                        == .suppressed(
                            reason:
                                "the deadline passed while the host was unavailable; the overdue reminder replaces it")
                })
            #expect(suppressed.filter { $0.rule == .proposalFollowUp }.count == 1)
            let audited = try host.application.all(AuditEvent.self).filter { $0.action == "reminder.recovery-skipped" }
            #expect(Set(audited.flatMap(\.affected)) == Set(suppressed.map(\.id.rawValue)))
            #expect(host.recoveryNotes.filter { $0.hasPrefix("skipped reminder") }.count == 3)

            await host.runtime.runOnce()
            testHost.advance(minutes: 5)
            await host.runtime.runOnce()
            // The permit gets the single overdue reminder, and none of the reminders it missed.
            let permitReminders = try host.application.all(Reminder.self).filter { $0.subject == .task(permit.id) }
            let fired = permitReminders.filter { $0.state.name == "delivered" }
            #expect(fired.map(\.rule) == [.overdue])
            #expect(TaskNotifications.presentations(of: permit.id, center: center) == 1)
            // No proposal is followed up more than once on the day the host resumed.
            let followUps = center.presented.filter { $0.presentation.categoryIdentifier == "LISA_EVENT_PROPOSAL" }
            for proposal in proposals {
                let reminderIDs = Set(
                    try host.application.all(Reminder.self).filter { $0.subject == .proposal(proposal.id) }.map(
                        \.id.rawValue))
                let intents = Set(
                    try host.application.all(NotificationIntent.self).filter { intent in
                        if case .reminder(let id) = intent.subject { return reminderIDs.contains(id.rawValue) }
                        return false
                    }.map(\.id.rawValue))
                let count = followUps.filter { intents.contains($0.presentation.notificationID) }.count
                #expect(count <= 1, "\(proposal.title) was followed up \(count) times on the day the host resumed")
            }
            host.close()
        }
    }

    @Test("Downtime across the brief time sends one catch-up brief within the window and records a later one skipped")
    func catchUpBriefWithinTheWindowOnly() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("2026-11-16T05:00"), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            await host.runtime.runOnce()
            host.close()

            // Back at 08:00 on Monday, 90 minutes after the 06:30 brief time: within the four-hour window.
            testHost.clock.set(at("2026-11-16T08:00"))
            host = try testHost.open()
            await host.runtime.runOnce()
            try testHost.restart(&host)
            await host.runtime.runOnce()
            let briefs = { center.presented.filter { $0.presentation.categoryIdentifier == "LISA_BRIEF" }.count }
            let emails = {
                try host.recorder.recent(limit: 100).filter { $0.subject?.hasPrefix("Your Lisa brief") == true }
            }
            #expect(briefs() == 1)
            #expect(try emails().count == 1)
            host.close()

            // Back at 11:00 on Tuesday, four and a half hours after the brief time: the brief is kept for the app but
            // not sent, and the skip is recorded.
            testHost.clock.set(at("2026-11-17T11:00"))
            host = try testHost.open()
            await host.runtime.runOnce()
            #expect(briefs() == 1)
            #expect(try emails().count == 1)
            #expect(try host.application.brief(for: TestTime.date("2026-11-17")) != nil)
            let skipped = try host.application.all(AuditEvent.self).filter { $0.action == "brief.catch-up-skipped" }
            #expect(skipped.count == 1)
            #expect(skipped.first?.outcome == .skipped)
            let tuesday = try host.application.all(NotificationIntent.self).filter {
                $0.occurrenceKey.contains("2026-11-17") && $0.category == .brief
            }
            #expect(tuesday.map(\.state) == [.expired])
            host.close()
        }
    }
}
