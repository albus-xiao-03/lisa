// Unit tests for L11, planning (PLAN-02, PLAN-03, PLAN-05; D-15): proposed blocks respect busy events, protected time,
// held blocks, other proposals, windows, buffers, durations, splitting and deadlines; ordering follows the documented
// baseline with stable tie-breaking; ideas stay within the exploration budget and the allocation cap; work that does
// not fit is reported with a reason; uncertain availability makes proposals provisional.

import Foundation
import LisaDomain
import LisaPlanning
import LisaTime
import Testing

@Suite("L11 — Planning: hard constraints and deterministic ordering", .tags(.unit))
struct L11PlanningTests {
    private let zone = PlanningFixture.zone

    private func settings(
        windows: [(String, String)] = [("09:00", "12:00")], protected: [(String, String)] = [], buffer: Int = 0,
        allocation: Double = 1, budget: Int = 60, weekdays: Set<Weekday> = Set(Weekday.allCases)
    ) -> PlanningSettings {
        PlanningSettings(
            windows: windows.map {
                LocalWindow(start: TestTime.time($0.0), end: TestTime.time($0.1), weekdays: weekdays)
            },
            protectedTime: protected.map { LocalWindow(start: TestTime.time($0.0), end: TestTime.time($0.1)) },
            bufferMinutes: buffer, maximumAllocation: allocation, ideaExplorationBudgetMinutes: budget)
    }

    private func task(
        _ id: String, minutes: Int = 30, priority: TaskPriority = .normal, due: String? = nil,
        splittable: Bool = false, createdAt: Date = PlanningFixture.createdAt
    ) -> PlanningItem {
        PlanningFixture.item(
            .task, id: id, minutes: minutes, priority: priority,
            deadline: due.map { .at(instant: TestTime.instant("2026-11-16T\($0)", in: TestTime.newYork), zone: zone) },
            splittable: splittable, createdAt: createdAt)
    }

    private func idea(_ id: String, minutes: Int = 30, priority: TaskPriority = .normal) -> PlanningItem {
        PlanningFixture.item(.idea, id: id, minutes: minutes, priority: priority)
    }

    private func plan(
        tasks: [PlanningItem] = [], ideas: [PlanningItem] = [], calendar: [CalendarBlock] = [],
        settings: PlanningSettings, previous: [PlanBlock] = [], rejected: [RejectedSuggestion] = [],
        uncertain: Bool = false, date: String = "2026-11-16", now: Date = PlanningFixture.now
    ) -> (input: PlanningInput, output: PlanningOutput) {
        let input = PlanningFixture.input(
            calendar: calendar, tasks: tasks, ideas: ideas, settings: settings, previousBlocks: previous,
            rejected: rejected, availabilityUncertain: uncertain, date: TestTime.date(date), now: now)
        return (input, DeterministicPlanner.plan(input))
    }

    private func local(_ block: PlanBlock) -> String {
        PlanConstraintCheck.describe(block.range, in: zone.timeZone)
    }

    private func times(of item: PlanningItem, in output: PlanningOutput) -> [String] {
        output.blocks.filter { $0.subject == item.subject }.map(local)
    }

    private func reason(for item: PlanningItem, in output: PlanningOutput) -> String? {
        output.unscheduled.first { $0.subject == item.subject }?.reason
    }

    @Test("Proposals avoid busy events, protected time and each other")
    func proposalsAvoidBusyProtectedAndEachOther() {
        let items = [task("a"), task("b"), task("c")]
        let (input, output) = plan(
            tasks: items, calendar: [PlanningFixture.busy("busy-1", "09:30", "10:00")],
            settings: settings(protected: [("10:30", "11:00")]))
        #expect(items.map { times(of: $0, in: output) } == [["09:00–09:30"], ["10:00–10:30"], ["11:00–11:30"]])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Entries marked free are shown but do not block time")
    func freeEntriesDoNotBlock() {
        let free = PlanningFixture.busy("free-1", "09:00", "10:00", title: "Optional webinar", blocksTime: false)
        let item = task("a")
        let (_, output) = plan(tasks: [item], calendar: [free], settings: settings())
        #expect(times(of: item, in: output) == ["09:00–09:30"])
        let shown = output.blocks.first { $0.kind == .fixedEvent }
        #expect(shown?.explanation == "Calendar entry marked free")
    }

    @Test("Nothing is placed outside the planning windows, including on days the windows do not cover")
    func windowsBoundPlacement() {
        let first = task("a", minutes: 45)
        let second = task("b", minutes: 45)
        let (input, output) = plan(
            tasks: [first, second], settings: settings(windows: [("09:00", "10:00"), ("14:00", "15:00")]))
        #expect(times(of: first, in: output) == ["09:00–09:45"])
        #expect(times(of: second, in: output) == ["14:00–14:45"])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])

        // 2026-11-17 is a Tuesday; these windows apply on Mondays only.
        let tuesday = plan(tasks: [first], settings: settings(weekdays: [.monday]), date: "2026-11-17")
        #expect(tuesday.output.blocks.isEmpty)
        #expect(reason(for: first, in: tuesday.output) != nil)
    }

    @Test("A configured buffer is kept around busy events; without one, no travel time is invented")
    func bufferIsExplicit() {
        let event = PlanningFixture.busy("busy-1", "10:00", "11:00")
        let hour = task("hour", minutes: 60)
        let withBuffer = plan(tasks: [hour], calendar: [event], settings: settings(buffer: 15))
        #expect(times(of: hour, in: withBuffer.output) == [])
        #expect(reason(for: hour, in: withBuffer.output) != nil)
        #expect(PlanConstraintCheck.violations(of: withBuffer.output, for: withBuffer.input) == [])

        let shorter = task("shorter", minutes: 45)
        let fits = plan(tasks: [shorter], calendar: [event], settings: settings(buffer: 15))
        #expect(times(of: shorter, in: fits.output) == ["09:00–09:45"])

        let noBuffer = plan(tasks: [hour], calendar: [event], settings: settings())
        #expect(times(of: hour, in: noBuffer.output) == ["09:00–10:00"])
    }

    @Test("Work is split only when marked splittable, into parts of at least 15 minutes")
    func splittingNeedsPermission() {
        let calendar = [
            PlanningFixture.busy("busy-1", "09:45", "10:50"), PlanningFixture.busy("busy-2", "11:00", "11:15"),
        ]
        let whole = task("whole", minutes: 90)
        let unsplit = plan(tasks: [whole], calendar: calendar, settings: settings())
        #expect(times(of: whole, in: unsplit.output) == [])
        #expect(
            reason(for: whole, in: unsplit.output)
                == "No free interval of 90 minutes is left in today's planning windows")

        let parts = task("parts", minutes: 90, splittable: true)
        let split = plan(tasks: [parts], calendar: calendar, settings: settings())
        // The 10-minute gap at 10:50–11:00 is too short for a part.
        #expect(times(of: parts, in: split.output) == ["09:00–09:45", "11:15–12:00"])
        let blocks = split.output.blocks.filter { $0.subject == parts.subject }
        #expect(blocks.map(\.blockID) == ["\(parts.subject.key)#0", "\(parts.subject.key)#1"])
        #expect(blocks.allSatisfy { $0.explanation.contains("split into 2 parts") })
        #expect(PlanConstraintCheck.violations(of: split.output, for: split.input) == [])
    }

    @Test("Deadlines bound placement; work that cannot finish in time, or whose deadline passed, is reported")
    func deadlineBoundaries() {
        let early = task("early", due: "09:20")
        let blocked = task("blocked", due: "10:00")
        let passed = task("passed", due: "06:00")
        let fits = task("fits", due: "11:00")
        let (input, output) = plan(
            tasks: [early, blocked, passed, fits], calendar: [PlanningFixture.busy("busy-1", "09:15", "10:30")],
            settings: settings())
        #expect(reason(for: early, in: output) == "No free interval of 30 minutes is left before the deadline")
        #expect(reason(for: blocked, in: output) == "No free interval of 30 minutes is left before the deadline")
        #expect(reason(for: passed, in: output) == "The deadline has passed")
        #expect(times(of: fits, in: output) == ["10:30–11:00"])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Baseline order: deadline tasks by deadline, other tasks by priority, then ideas")
    func baselineOrdering() {
        let ideaItem = idea("idea", priority: .urgent)
        let urgent = task("urgent", priority: .urgent)
        let high = task("high", priority: .high)
        let dueLate = task("due-late", priority: .normal, due: "12:00")
        let dueSoon = task("due-soon", priority: .low, due: "11:00")
        let (input, output) = plan(
            tasks: [urgent, high, dueLate, dueSoon], ideas: [ideaItem], settings: settings())
        #expect(times(of: dueSoon, in: output) == ["09:00–09:30"])
        #expect(times(of: dueLate, in: output) == ["09:30–10:00"])
        #expect(times(of: urgent, in: output) == ["10:00–10:30"])
        #expect(times(of: high, in: output) == ["10:30–11:00"])
        #expect(times(of: ideaItem, in: output) == ["11:00–11:30"])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Ties break by creation time and then by subject, so input order never changes the plan")
    func stableTieBreaking() {
        let later = task("a-later", createdAt: TestTime.instant("2026-11-14T12:00", in: TestTime.newYork))
        let earlier = task("z-earlier", createdAt: TestTime.instant("2026-11-12T12:00", in: TestTime.newYork))
        let sameB = task("b-same")
        let sameA = task("a-same")
        let forward = plan(tasks: [later, earlier, sameB, sameA], settings: settings()).output
        #expect(times(of: earlier, in: forward) == ["09:00–09:30"])
        #expect(times(of: sameA, in: forward) == ["09:30–10:00"])
        #expect(times(of: sameB, in: forward) == ["10:00–10:30"])
        #expect(times(of: later, in: forward) == ["10:30–11:00"])
        let backward = plan(tasks: [sameA, sameB, earlier, later], settings: settings()).output
        #expect(forward == backward)
    }

    @Test("Ideas stay within the daily exploration budget")
    func ideasWithinBudget() {
        let ideas = [idea("idea-1"), idea("idea-2"), idea("idea-3")]
        let (_, output) = plan(ideas: ideas, settings: settings(budget: 60))
        #expect(ideas.map { times(of: $0, in: output) } == [["09:00–09:30"], ["09:30–10:00"], []])
        #expect(reason(for: ideas[2], in: output) == "The 60-minute exploration budget for the day is used")
    }

    @Test("The planner never fills more than the maximum allocation of free time; the default leaves time free")
    func maximumAllocation() {
        let items = (1...8).map { task("task-\($0)") }
        let half = plan(tasks: items, settings: settings(windows: [("09:00", "13:00")], allocation: 0.5)).output
        #expect(half.blocks.count == 4)
        #expect(half.unscheduled.count == 4)
        #expect(half.unscheduled.allSatisfy { $0.reason == "Planning more would exceed 50% of the free time" })

        var defaults = PlanningSettings(
            windows: [LocalWindow(start: TestTime.time("09:00"), end: TestTime.time("13:00"))])
        defaults.bufferMinutes = 0
        let standard = plan(tasks: items, settings: defaults).output
        #expect(standard.blocks.count == 6)
        #expect(standard.unscheduled.count == 2)
    }

    @Test("An item that fits nowhere is reported as having no free interval, not as hitting the cap")
    func reasonPrecedence() {
        let items = (1...4).map { task("task-\($0)") } + [task("too-long", minutes: 300)]
        let (_, output) = plan(tasks: items, settings: settings(windows: [("09:00", "13:00")], allocation: 0.5))
        #expect(
            reason(for: items[4], in: output) == "No free interval of 300 minutes is left in today's planning windows")
    }

    @Test("Time before now is unavailable today, rounded up to five minutes")
    func pastTimeIsUnavailable() {
        let item = task("a")
        let (input, output) = plan(
            tasks: [item], settings: settings(), now: TestTime.instant("2026-11-16T09:07", in: TestTime.newYork))
        #expect(times(of: item, in: output) == ["09:10–09:40"])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("With uncertain availability every proposal is provisional and the plan says so")
    func uncertainAvailabilityIsProvisional() {
        let item = task("a")
        let (_, output) = plan(
            tasks: [item], calendar: [PlanningFixture.busyEvent], settings: settings(), uncertain: true)
        let proposals = output.blocks.filter { $0.kind != .fixedEvent }
        #expect(!proposals.isEmpty)
        #expect(proposals.allSatisfy { $0.provisional && $0.explanation.contains("provisional") })
        #expect(output.blocks.filter { $0.kind == .fixedEvent }.allSatisfy { !$0.provisional })
        #expect(output.warnings.contains("Some calendar data is stale or incomplete; proposed times are provisional"))
    }

    @Test("A rejected suggestion is not reintroduced until something relevant changes")
    func rejectedSuggestions() {
        let item = task("a")
        let rejection = RejectedSuggestion(
            subjectKey: item.subject.key, inputFingerprint: item.fingerprint(on: PlanningFixture.date))
        let (_, output) = plan(tasks: [item], settings: settings(), rejected: [rejection])
        #expect(times(of: item, in: output) == [])
        #expect(
            reason(for: item, in: output) == "You rejected this suggestion; it returns when something relevant changes")

        let changed = task("a", minutes: 45)
        let (_, replanned) = plan(tasks: [changed], settings: settings(), rejected: [rejection])
        #expect(times(of: changed, in: replanned) == ["09:00–09:45"])
    }

    @Test("Locked and completed blocks are kept exactly, and new proposals go around them")
    func lockedAndCompletedBlocksArePreserved() {
        let lockedItem = task("locked")
        let doneItem = task("done")
        let newItem = task("new")
        let locked = PlanningFixture.block("locked-block", for: lockedItem, "09:00", "09:30", state: .locked)
        let done = PlanningFixture.block("done-block", for: doneItem, "09:30", "10:00", state: .completed)
        let (input, output) = plan(
            tasks: [lockedItem, doneItem, newItem], settings: settings(), previous: [locked, done])
        #expect(output.blocks.contains(locked))
        #expect(output.blocks.contains(done))
        #expect(times(of: lockedItem, in: output) == ["09:00–09:30"])
        #expect(times(of: doneItem, in: output) == ["09:30–10:00"])
        #expect(times(of: newItem, in: output) == ["10:00–10:30"])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("An accepted block is kept while valid, and placed again with a warning once the calendar conflicts")
    func acceptedBlocks() {
        let item = task("a")
        let accepted = PlanningFixture.block("accepted-block", for: item, "11:00", "11:30", state: .accepted)
        let kept = plan(tasks: [item], settings: settings(), previous: [accepted]).output
        #expect(kept.blocks.filter { $0.subject == item.subject } == [accepted])

        let conflict = PlanningFixture.busy("busy-1", "11:00", "12:00")
        let (input, moved) = plan(tasks: [item], calendar: [conflict], settings: settings(), previous: [accepted])
        #expect(times(of: item, in: moved) == ["09:00–09:30"])
        #expect(moved.warnings.contains("\"a\" was accepted but now conflicts with the calendar; it was placed again"))
        #expect(PlanConstraintCheck.violations(of: moved, for: input) == [])
    }
}
