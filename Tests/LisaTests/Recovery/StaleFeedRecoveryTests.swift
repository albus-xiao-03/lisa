// Recovery tests for §16.3, a stale feed that then returns successfully with updated data (CAL-02, INGEST-01, PLAN-05,
// BRIEF-01; D-32): a calendar feed that kept failing until it went stale is labeled so in the plan and the brief while
// its known events stay; when it returns with updated data, the moved and added events are reconciled, the source is
// fresh again, availability is certain and the plan is rebuilt around the updated events.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("§16.3 — A stale feed returning successfully with updated data", .tags(.recovery))
struct StaleFeedRecoveryTests {
    private let today = TestTime.date("2026-11-16")
    private let standup = SyntheticEvent(
        uid: "stale-standup@example.com", title: "Synthetic standup", start: "2026-11-16T09:00",
        end: "2026-11-16T09:30")
    private let review = SyntheticEvent(
        uid: "stale-review@example.com", title: "Synthetic review", start: "2026-11-16T10:30", end: "2026-11-16T11:30")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    @Test("A feed failing until stale keeps its events and is labeled; when it returns, its updates are reconciled")
    func staleFeedRecoversWithUpdates() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            try SourceFiles.write(SyntheticEvent.calendar([standup, review]), to: file, modifiedAt: at("06:00"))
            var owner = TestHost.owner()
            owner.planning = PlanningFixture.settings
            // Stale 30 minutes after the last successful refresh.
            let source = SourceFiles.calendarSource(file, staleAfterSeconds: 1_800)
            let testHost = TestHost(scratch: scratch, now: at("07:00"), owner: owner, sources: [source])
            var host = try testHost.open()
            let task = try host.application.createTask(
                TaskDraft(title: "Synthetic summary", priority: .high, estimatedMinutes: 30), by: .localOwner)
            await host.runtime.runOnce()

            // The feed breaks, keeps failing, and the host restarts while it is stale.
            try SourceFiles.write("BEGIN:VCALENDAR\r\nunavailable\r\n", to: file, modifiedAt: at("07:05"))
            for time in ["07:06", "07:20", "07:40"] {
                testHost.clock.set(at(time))
                await host.runtime.runOnce()
            }
            try testHost.restart(&host)
            let stale = try #require(try host.application.all(Source.self).first { $0.configurationKey == "calendar" })
            #expect(stale.freshness(at: testHost.clock.now()) == .stale)
            #expect(stale.isFailing)
            #expect(try host.application.all(CalendarOccurrence.self).filter(\.blocksTime).count == 2)
            #expect(try host.application.rundown(for: today)?.basis.availabilityUncertain == true)
            let staleBrief = try host.application.services.briefs.generate(for: today)
            #expect(staleBrief.text.contains("Could not check Work calendar"))

            // It returns with updated data: the standup moved and a planning session was added.
            let movedStandup = SyntheticEvent(
                uid: standup.uid, title: standup.title, start: "2026-11-16T09:30", end: "2026-11-16T10:00")
            let planning = SyntheticEvent(
                uid: "stale-planning@example.com", title: "Synthetic planning", start: "2026-11-16T11:30",
                end: "2026-11-16T12:00")
            try SourceFiles.write(
                SyntheticEvent.calendar([movedStandup, review, planning]), to: file, modifiedAt: at("07:44"))
            testHost.clock.set(at("07:45"))
            await host.runtime.runOnce()

            let fresh = try #require(try host.application.record(Source.self, id: stale.id))
            #expect(fresh.lastFailure == nil)
            #expect(fresh.freshness(at: testHost.clock.now()) == .fresh)
            let occurrences = Dictionary(
                uniqueKeysWithValues: try host.application.all(CalendarOccurrence.self).map { ($0.uid, $0) })
            #expect(occurrences.count == 3)
            let updated = try #require(occurrences[standup.uid])
            #expect(
                PlanConstraintCheck.describe(
                    updated.range(in: TestTime.newYork.timeZone), in: TestTime.newYork.timeZone) == "09:30–10:00")
            #expect(updated.changeSequence == 1)
            #expect(occurrences[planning.uid]?.blocksTime == true)
            let plan = try #require(try host.application.rundown(for: today))
            #expect(!plan.basis.availabilityUncertain)
            #expect(StoredPlanCheck.overlaps(in: plan, with: Array(occurrences.values), zone: TestTime.newYork).isEmpty)
            #expect(plan.blocks.contains { $0.subject == .task(task.id) && !$0.provisional })
            let freshBrief = try host.application.services.briefs.generate(for: today)
            #expect(!freshBrief.text.contains("Could not check Work calendar"))
            #expect(freshBrief.version == staleBrief.version + 1)
            host.close()
        }
    }
}
