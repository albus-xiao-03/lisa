// Recovery tests for §16.3, a changed calendar occurrence that already has a reminder (CAL-02, REM-01, PLAN-04,
// NOTIFY-01; D-15, D-16, D-27): an owner-accepted plan block has its start reminder when a calendar refresh moves an
// event over it. The block is placed again with a warning, its obsolete reminder is cancelled and never fires, any
// reminder that remains follows the block's current start, and the change is notified to the device once.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("§16.3 — A changed calendar occurrence with an existing reminder", .tags(.recovery))
struct ChangedOccurrenceReminderTests {
    private let zone = TestTime.newYork
    private let review = SyntheticEvent(
        uid: "changed-review@example.com", title: "Synthetic design review", start: "2026-11-16T10:00",
        end: "2026-11-16T11:00")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    @Test(
        "A moved event over an accepted block re-places it; its old reminder never fires; the change is notified once")
    func movedEventOverAnAcceptedBlock() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            try SourceFiles.write(SyntheticEvent.calendar([review]), to: file, modifiedAt: at("06:00"))
            let center = ScriptedNotificationCenter()
            var owner = TestHost.owner()
            owner.planning = PlanningFixture.settings
            owner.notifications.notifyBriefAvailability = false
            let testHost = TestHost(
                scratch: scratch, now: at("07:00"), owner: owner, sources: [SourceFiles.calendarSource(file)],
                localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(
                    title: "Synthetic proposal draft", priority: .high, deadline: SyntheticTask.due(at("12:00")),
                    estimatedMinutes: 30),
                by: .localOwner)
            await host.runtime.runOnce()
            var plan = try #require(try host.application.rundown(for: TestTime.date("2026-11-16")))
            let taskSubject = PlanSubject.task(task.id)
            let block = try #require(plan.blocks.first(where: { $0.subject == taskSubject }))
            #expect(PlanConstraintCheck.describe(block.range, in: zone.timeZone) == "09:00–09:30")
            plan = try host.application.actOnPlanBlock(
                .accept, planID: plan.id, blockID: block.blockID, expectedRevision: plan.revision, by: .localOwner)
            let blockReminders = {
                try host.application.all(Reminder.self).filter { $0.rule == .planBlockStart }
            }
            let original = try #require(try blockReminders().first)
            #expect(original.dueAt == at("08:50"))

            // The review moves to 09:00–10:00, over the accepted block.
            var moved = review
            moved.start = "2026-11-16T09:00"
            moved.end = "2026-11-16T10:00"
            try SourceFiles.write(SyntheticEvent.calendar([moved]), to: file, modifiedAt: at("07:30"))
            testHost.clock.set(at("07:30"))
            await host.runtime.runOnce()

            plan = try #require(try host.application.rundown(for: TestTime.date("2026-11-16")))
            let blocks = plan.blocks.map { "\($0.title) \($0.state)" }
            #expect(
                plan.warnings.contains { $0.contains("conflicts with the calendar") },
                "warnings: \(plan.warnings); changes: \(plan.changes); blocks: \(blocks)")
            let busy = try host.application.all(CalendarOccurrence.self).filter(\.blocksTime)
            let current = try #require(plan.blocks.first(where: { $0.subject == taskSubject }))
            #expect(busy.allSatisfy { !$0.range(in: zone.timeZone).overlaps(current.range) })
            #expect(try host.application.record(Reminder.self, id: original.id)?.state.name == "cancelled")

            for time in ["08:50", "08:55", "09:30", "10:00", "10:30", "11:00"] {
                testHost.clock.set(at(time))
                await host.runtime.runOnce()
            }
            // The obsolete reminder never fired; any remaining one follows the block's current start.
            let presentedReminders = Set(center.presented.map(\.presentation.subjectID))
            #expect(!presentedReminders.contains(original.id.rawValue))
            for reminder in try blockReminders() where reminder.id != original.id {
                #expect(reminder.dueAt == current.range.start.addingTimeInterval(-10 * 60))
            }
            // The device heard about the change once.
            let changes = center.presented.filter { $0.presentation.categoryIdentifier == "LISA_COMMITMENT_CHANGE" }
            #expect(changes.count == 1)
            host.close()
        }
    }
}
