// Integration tests for L12, replanning (PLAN-02, PLAN-04, CAL-02, IDEA-01; D-15, D-32), including the §16.2 fixture
// at service level: the stored plan for 2026-11-16 is computed from a configured calendar, an owner-created task and a
// captured idea, then replanned when the 09:00–09:30 event arrives through a calendar refresh. New commitments (an
// event or a task) move affected proposed blocks, keep locked and completed blocks exactly, and never put a proposed
// block over a busy event.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("L12 — Replanning", .tags(.integration))
struct L12ReplanningTests {
    private let zone = PlanningFixture.zone
    private let busyEvent = SyntheticEvent(
        uid: "fixture-event-1000@example.com", title: "Fixture busy event", start: "2026-11-16T10:00",
        end: "2026-11-16T11:00")
    private let addedEvent = SyntheticEvent(
        uid: "fixture-event-0900@example.com", title: "Fixture added event", start: "2026-11-16T09:00",
        end: "2026-11-16T09:30")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: zone)
    }

    /// The §16.2 settings: window 09:00–12:00, zero buffer, every other setting at its documented default.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.planning = PlanningFixture.settings
        return owner
    }

    /// The fixture's items: a confirmed 30-minute task due at 10:00 with a higher priority than the 30-minute idea,
    /// which is available for planning.
    private func addFixtureItems(to host: LisaHost) throws -> (task: LisaTask, idea: Idea) {
        let app = host.application
        let task = try app.createTask(
            TaskDraft(
                title: "Fixture task", priority: .high, deadline: .at(instant: at("10:00"), zone: zone),
                estimatedMinutes: 30),
            by: .localOwner)
        let captured = try #require(
            try app.capture(CaptureRequest(kind: .idea, text: "Fixture idea", channel: .commandLine), by: .localOwner)
                .idea)
        let edited = try app.editIdea(
            captured.id, expectedRevision: captured.revision, IdeaEdit(estimatedMinutes: 30), by: .localOwner)
        let idea = try app.moveIdea(
            captured.id, to: .availableForPlanning, expectedRevision: edited.revision, by: .localOwner)
        return (task, idea)
    }

    private func plan(_ host: LisaHost) throws -> Plan {
        try #require(try host.application.rundown(for: PlanningFixture.date))
    }

    private func times(_ subject: PlanSubject, _ plan: Plan) -> [String] {
        StoredPlanCheck.times(of: subject, in: plan, zone: zone)
    }

    private func busyOccurrences(_ host: LisaHost) throws -> [CalendarOccurrence] {
        try host.application.all(CalendarOccurrence.self).filter(\.blocksTime)
    }

    /// A host with the fixture's calendar file, synchronized once at 07:00.
    private func fixtureHost(_ scratch: ScratchDirectory) async throws -> (TestHost, LisaHost, URL) {
        let file = scratch.path("calendars", "work.ics")
        try SourceFiles.write(SyntheticEvent.calendar([busyEvent]), to: file, modifiedAt: at("06:00"))
        let testHost = TestHost(
            scratch: scratch, now: at("07:00"), owner: owner(), sources: [SourceFiles.calendarSource(file)])
        let host = try testHost.open()
        return (testHost, host, file)
    }

    /// Adds `events` to the calendar file and lets the next synchronization find them.
    private func refresh(
        _ host: LisaHost, _ testHost: TestHost, file: URL, events: [SyntheticEvent]
    ) async throws {
        try SourceFiles.write(SyntheticEvent.calendar(events), to: file, modifiedAt: testHost.clock.now())
        testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
        await host.runtime.runOnce()
    }

    @Test("§16.2 at service level: the stored plan is replanned when the 09:00–09:30 event arrives")
    func fixtureReplannedAfterTheNewEvent() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, file) = try await fixtureHost(scratch)
            let (task, idea) = try addFixtureItems(to: host)
            await host.runtime.runOnce()
            let baseline = try plan(host)
            #expect(times(.task(task.id), baseline) == ["09:00–09:30"])
            #expect(times(.idea(idea.id), baseline) == ["09:30–10:00"])
            let fixed = baseline.blocks.filter { $0.kind == .fixedEvent }
            #expect(fixed.map { PlanConstraintCheck.describe($0.range, in: zone.timeZone) } == ["10:00–11:00"])
            #expect(!baseline.basis.availabilityUncertain)

            try await refresh(host, testHost, file: file, events: [busyEvent, addedEvent])
            let replanned = try plan(host)
            #expect(replanned.id == baseline.id)
            #expect(replanned.revision > baseline.revision)
            #expect(times(.task(task.id), replanned) == ["09:30–10:00"])
            // The idea moves to another valid slot (11:00–11:30 per D-15), or is reported unscheduled with a reason.
            let ideaTimes = times(.idea(idea.id), replanned)
            if ideaTimes.isEmpty {
                #expect(replanned.unscheduled.contains { $0.subject == .idea(idea.id) && !$0.reason.isEmpty })
            } else {
                #expect(ideaTimes == ["11:00–11:30"])
            }
            #expect(StoredPlanCheck.overlaps(in: replanned, with: try busyOccurrences(host), zone: zone).isEmpty)
            #expect(!replanned.changes.isEmpty)
            host.close()
        }
    }

    @Test("A new busy event moves only the proposed blocks it affects; locked and completed blocks stay exactly")
    func lockedAndCompletedBlocksSurviveANewEvent() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, file) = try await fixtureHost(scratch)
            let (task, idea) = try addFixtureItems(to: host)
            let errand = try host.application.createTask(
                TaskDraft(title: "Fixture errand", estimatedMinutes: 30), by: .localOwner)
            await host.runtime.runOnce()
            var current = try plan(host)
            let ideaSubject = PlanSubject.idea(idea.id)
            let errandSubject = PlanSubject.task(errand.id)
            let ideaBlock = try #require(current.blocks.first(where: { $0.subject == ideaSubject }))
            current = try host.application.actOnPlanBlock(
                .lock, planID: current.id, blockID: ideaBlock.blockID, expectedRevision: current.revision,
                by: .localOwner)
            let errandBlock = try #require(current.blocks.first(where: { $0.subject == errandSubject }))
            current = try host.application.actOnPlanBlock(
                .complete, planID: current.id, blockID: errandBlock.blockID, expectedRevision: current.revision,
                by: .localOwner)
            // Calendar events are locked blocks too; the owner-held ones are the idea and the errand.
            let held = current.blocks.filter {
                $0.kind != .fixedEvent && ($0.state == .locked || $0.state == .completed)
            }
            #expect(held.count == 2)

            try await refresh(host, testHost, file: file, events: [busyEvent, addedEvent])
            let replanned = try plan(host)
            for block in held {
                let kept = replanned.blocks.first { $0.blockID == block.blockID }
                #expect(kept?.range == block.range)
                #expect(kept?.state == block.state)
            }
            #expect(StoredPlanCheck.overlaps(in: replanned, with: try busyOccurrences(host), zone: zone).isEmpty)
            // The task, due at 10:00, is either placed in time and clear of every event, or reported unscheduled.
            let taskSubject = PlanSubject.task(task.id)
            let taskBlocks = replanned.blocks.filter { $0.subject == taskSubject }
            if taskBlocks.isEmpty {
                #expect(replanned.unscheduled.contains { $0.subject == taskSubject })
            } else {
                #expect(taskBlocks.allSatisfy { $0.range.end <= at("10:00") })
            }
            host.close()
        }
    }

    @Test("A new confirmed task with an earlier deadline takes the slot it needs; the locked idea stays put")
    func newTaskMovesProposedBlocks() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host, _) = try await fixtureHost(scratch)
            let (task, idea) = try addFixtureItems(to: host)
            await host.runtime.runOnce()
            var current = try plan(host)
            let ideaBlock = try #require(current.blocks.first { $0.subject == .idea(idea.id) })
            current = try host.application.actOnPlanBlock(
                .lock, planID: current.id, blockID: ideaBlock.blockID, expectedRevision: current.revision,
                by: .localOwner)

            let urgent = try host.application.createTask(
                TaskDraft(
                    title: "Fixture urgent call", priority: .urgent,
                    deadline: .at(instant: at("09:30"), zone: zone), estimatedMinutes: 30),
                by: .localOwner)
            let replanned = try plan(host)
            #expect(times(.task(urgent.id), replanned) == ["09:00–09:30"])
            #expect(replanned.blocks.first { $0.blockID == ideaBlock.blockID }?.range == ideaBlock.range)
            #expect(replanned.blocks.first { $0.blockID == ideaBlock.blockID }?.state == .locked)
            // The fixture task can no longer finish by 10:00, so it is reported rather than placed late.
            #expect(times(.task(task.id), replanned).isEmpty)
            #expect(replanned.unscheduled.contains { $0.subject == .task(task.id) && !$0.reason.isEmpty })
            #expect(StoredPlanCheck.overlaps(in: replanned, with: try busyOccurrences(host), zone: zone).isEmpty)
            host.close()
        }
    }
}
