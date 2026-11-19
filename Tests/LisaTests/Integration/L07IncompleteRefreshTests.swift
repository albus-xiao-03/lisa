// Integration tests for L07, incomplete calendar refresh (CAL-01, CAL-02, PLAN-02, PLAN-05, INGEST-01; D-32, D-37):
// unreadable data, a refresh larger than one pass allows, and a configured calendar file that is missing keep every
// known event and mark the source failing; the plan then labels availability uncertain and places no work over the
// known events. Only a successful complete refresh removes an event.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaPorts
import LisaTime
import Testing

@Suite("L07 — Incomplete refresh", .tags(.integration))
struct L07IncompleteRefreshTests {
    private let today = TestTime.date("2026-11-16")
    private let standup = SyntheticEvent(
        uid: "l07-standup@example.com", title: "Synthetic standup", start: "2026-11-16T09:00", end: "2026-11-16T10:00")
    private let review = SyntheticEvent(
        uid: "l07-review@example.com", title: "Synthetic review", start: "2026-11-16T10:30", end: "2026-11-16T11:30")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Planning 09:00–12:00 with no buffer, as in the §16.2 fixture.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.planning = PlanningFixture.settings
        return owner
    }

    /// The occurrences that still block time, by UID.
    private func busy(_ host: LisaHost) throws -> [String: CalendarOccurrence] {
        Dictionary(
            uniqueKeysWithValues: try host.application.all(CalendarOccurrence.self).filter(\.blocksTime).map {
                ($0.uid, $0)
            })
    }

    private func calendarSource(_ host: LisaHost) throws -> Source {
        try #require(try host.application.all(Source.self).first { $0.configurationKey == "calendar" })
    }

    /// Opens the host with `source`, adds a confirmed 30-minute task and synchronizes once at 07:00.
    private func prepared(_ testHost: TestHost, file: URL) async throws -> (LisaHost, LisaTask) {
        try SourceFiles.write(SyntheticEvent.calendar([standup, review]), to: file, modifiedAt: at("06:00"))
        let host = try testHost.open()
        let task = try host.application.createTask(
            TaskDraft(title: "Synthetic write-up", priority: .high, estimatedMinutes: 30), by: .localOwner)
        await host.runtime.runOnce()
        #expect(try busy(host).count == 2)
        #expect(try host.application.rundown(for: today)?.basis.availabilityUncertain == false)
        return (host, task)
    }

    /// The checks after a refresh that failed: both events kept unchanged, and a plan that is uncertain and clear of
    /// them, with the task still planned.
    private func expectKnownEventsKept(
        _ host: LisaHost, before: [String: CalendarOccurrence], task: LisaTask, failure: SourceErrorClass
    ) throws {
        let after = try busy(host)
        #expect(after.keys.sorted() == before.keys.sorted())
        for (uid, occurrence) in before {
            #expect(after[uid]?.timing == occurrence.timing)
            #expect(after[uid]?.revision == occurrence.revision)
        }
        #expect(try calendarSource(host).lastFailure?.errorClass == failure)
        let plan = try #require(try host.application.rundown(for: today))
        #expect(plan.basis.availabilityUncertain)
        #expect(StoredPlanCheck.overlaps(in: plan, with: Array(after.values), zone: TestTime.newYork).isEmpty)
        let taskBlocks = plan.blocks.filter { $0.subject == .task(task.id) }
        #expect(taskBlocks.count == 1)
        #expect(taskBlocks.allSatisfy { $0.provisional })
    }

    @Test("A calendar that can no longer be read keeps every known event, and work stays clear of them")
    func unreadableCalendarKeepsEvents() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            let testHost = TestHost(
                scratch: scratch, now: at("07:00"), owner: owner(), sources: [SourceFiles.calendarSource(file)])
            let (host, task) = try await prepared(testHost, file: file)
            let before = try busy(host)
            try SourceFiles.write("BEGIN:VCALENDAR\r\nthis is not a calendar\r\n", to: file, modifiedAt: at("07:02"))
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            try expectKnownEventsKept(host, before: before, task: task, failure: .parse)
            host.close()
        }
    }

    @Test("A refresh with more data than one pass may read changes nothing it did not finish reading")
    func partialRefreshRemovesNothing() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("calendars")
            let file = directory.appendingPathComponent("work.ics")
            let source = HostSource(
                key: "calendar", name: "Work calendars", kind: .calendarFeed, syncIntervalSeconds: 300,
                access: .localDirectory(directory, .calendar))
            var testHost = TestHost(scratch: scratch, now: at("07:00"), owner: owner(), sources: [source])
            testHost.settings.syncLimits = SyncLimits(maxItems: 1)
            let (host, task) = try await prepared(testHost, file: file)
            let before = try busy(host)
            // The work calendar now lacks the review, and a second calendar file appears: two files exceed the one
            // item a pass may read, so the snapshot is incomplete.
            try SourceFiles.write(SyntheticEvent.calendar([standup]), to: file, modifiedAt: at("07:02"))
            try SourceFiles.write(
                SyntheticEvent.calendar([]), to: directory.appendingPathComponent("home.ics"), modifiedAt: at("07:02"))
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            try expectKnownEventsKept(host, before: before, task: task, failure: .partial)
            host.close()
        }
    }

    @Test("A configured calendar file that is missing during a refresh removes no event")
    func missingCalendarFileRemovesNothing() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            let testHost = TestHost(
                scratch: scratch, now: at("07:00"), owner: owner(), sources: [SourceFiles.calendarSource(file)])
            let (host, task) = try await prepared(testHost, file: file)
            let before = try busy(host)
            // The file is gone for a moment, as while another program replaces it.
            try FileManager.default.removeItem(at: file)
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            let after = try busy(host)
            #expect(after.keys.sorted() == before.keys.sorted())
            #expect(try calendarSource(host).isFailing)
            let plan = try #require(try host.application.rundown(for: today))
            #expect(plan.basis.availabilityUncertain)
            #expect(StoredPlanCheck.overlaps(in: plan, with: Array(before.values), zone: TestTime.newYork).isEmpty)
            #expect(plan.blocks.contains { $0.subject == .task(task.id) })
            host.close()
        }
    }

    @Test("Only a successful complete refresh removes an event, and the plan is then certain again")
    func completeRefreshRemovesAnEvent() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            let testHost = TestHost(
                scratch: scratch, now: at("07:00"), owner: owner(), sources: [SourceFiles.calendarSource(file)])
            let (host, _) = try await prepared(testHost, file: file)
            try SourceFiles.write("BEGIN:VCALENDAR\r\nbroken\r\n", to: file, modifiedAt: at("07:02"))
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            #expect(try busy(host).count == 2)

            try SourceFiles.write(SyntheticEvent.calendar([standup]), to: file, modifiedAt: at("07:10"))
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            #expect(try busy(host).keys.sorted() == [standup.uid])
            let removed = try #require(try host.application.all(CalendarOccurrence.self).first { $0.uid == review.uid })
            #expect(removed.status == .cancelled)
            #expect(removed.warnings.contains("no longer present in the calendar source"))
            let source = try calendarSource(host)
            #expect(source.lastFailure == nil)
            #expect(source.freshness(at: testHost.clock.now()) == .fresh)
            let plan = try #require(try host.application.rundown(for: today))
            #expect(!plan.basis.availabilityUncertain)
            #expect(
                StoredPlanCheck.overlaps(in: plan, with: Array(try busy(host).values), zone: TestTime.newYork).isEmpty)
            host.close()
        }
    }
}
