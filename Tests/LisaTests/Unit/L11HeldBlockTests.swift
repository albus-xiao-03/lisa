// Unit tests for L11 with held blocks and moves (PLAN-02, PLAN-04; D-15, D-52): a locked block that a new commitment
// overlaps stays put and is warned about; a held (locked, moved, completed or accepted) part of a splittable task
// leaves the rest planned under new block IDs, or reported unscheduled with the minutes left; a task that is not
// splittable stays as the owner placed it; and a move that breaks a hard constraint is refused.

import Foundation
import LisaDomain
import LisaPlanning
import LisaTime
import Testing

@Suite("L11 — Planning: held blocks and moves (D-52)", .tags(.unit))
struct L11HeldBlockTests {
    private let zone = PlanningFixture.zone

    private func settings(windows: [(String, String)] = [("09:00", "12:00")]) -> PlanningSettings {
        PlanningSettings(
            windows: windows.map { LocalWindow(start: TestTime.time($0.0), end: TestTime.time($0.1)) },
            maximumAllocation: 1)
    }

    private func report(minutes: Int = 90, splittable: Bool = true, due: String? = nil) -> PlanningItem {
        PlanningFixture.item(
            .task, id: "report", title: "Synthetic report", minutes: minutes, priority: .high,
            deadline: due.map { .at(instant: TestTime.instant("2026-11-16T\($0)", in: TestTime.newYork), zone: zone) },
            splittable: splittable)
    }

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    private func local(_ block: PlanBlock) -> String {
        PlanConstraintCheck.describe(block.range, in: zone.timeZone)
    }

    private func blocks(of item: PlanningItem, in output: PlanningOutput) -> [PlanBlock] {
        output.blocks.filter { $0.subject == item.subject }
    }

    private func minutes(_ blocks: [PlanBlock]) -> Int {
        Int(blocks.reduce(0) { $0 + $1.range.duration } / 60)
    }

    @Test("A locked block that a new busy event overlaps stays where it is, and the plan warns about it")
    func lockedBlockStaysWhenOverlapped() {
        let task = PlanningFixture.task
        let locked = PlanningFixture.block("task:fixture-task#0", for: task, "09:00", "09:30", state: .locked)
        let call = PlanningFixture.busy("board-call", "09:00", "10:00", title: "Board call")
        let input = PlanningFixture.input(calendar: [call], previousBlocks: [locked])
        let output = DeterministicPlanner.plan(input)
        #expect(blocks(of: task, in: output) == [locked])
        #expect(
            output.warnings.contains(
                "\"Fixture task\" is locked at a time that now overlaps \"Board call\" on the calendar"))
        #expect(!output.unscheduled.contains { $0.subject == task.subject })
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test(
        "A held part of a splittable task leaves the remaining time planned around it",
        arguments: [PlanBlockState.locked, .completed, .accepted])
    func heldPartLeavesRestPlanned(state: PlanBlockState) {
        let item = report()
        let held = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: state)
        let input = PlanningFixture.input(
            calendar: [], tasks: [item], ideas: [], settings: settings(), previousBlocks: [held])
        let output = DeterministicPlanner.plan(input)
        let parts = blocks(of: item, in: output)
        #expect(parts.contains(held))
        let added = parts.filter { $0 != held }
        #expect(added.map(local) == ["09:30–10:30"])
        #expect(added.map(\.blockID) == ["\(item.subject.key)#1"])
        #expect(added.allSatisfy { $0.state == .proposed && $0.explanation.contains("the remaining 60 minutes") })
        #expect(minutes(parts) == 90)
        #expect(output.unscheduled.isEmpty)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("A part the owner moved counts as held, and the rest of the task is planned around it")
    func movedPartCountsAsHeld() throws {
        let item = report()
        let first = DeterministicPlanner.plan(
            PlanningFixture.input(calendar: [], tasks: [item], ideas: [], settings: settings()))
        let proposed = try #require(blocks(of: item, in: first).first)
        #expect(local(proposed) == "09:00–10:30")
        let moved = try PlanBlockMove.moved(
            proposed, start: at("11:00"), end: at("11:30"), among: first.blocks, calendar: [],
            on: PlanningFixture.date, in: zone.timeZone)
        let input = PlanningFixture.input(
            calendar: [], tasks: [item], ideas: [], settings: settings(), previousBlocks: [moved])
        let output = DeterministicPlanner.plan(input)
        let parts = blocks(of: item, in: output)
        #expect(parts.contains(moved))
        #expect(parts.filter { $0 != moved }.map(local) == ["09:00–10:00"])
        #expect(Set(parts.map(\.blockID)).count == parts.count)
        #expect(minutes(parts) == 90)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("When the remaining time does not fit, it is reported unscheduled with the minutes left")
    func remainingTimeReportedWhenItDoesNotFit() {
        let item = report()
        let held = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: .locked)
        let output = DeterministicPlanner.plan(
            PlanningFixture.input(
                calendar: [], tasks: [item], ideas: [], settings: settings(windows: [("09:00", "10:00")]),
                previousBlocks: [held]))
        #expect(blocks(of: item, in: output) == [held])
        #expect(
            output.unscheduled.first { $0.subject == item.subject }?.reason
                == "No free time is left in today's planning windows for the remaining 60 minutes")

        let dueItem = report(due: "10:00")
        let dueHeld = PlanningFixture.block("\(dueItem.subject.key)#0", for: dueItem, "09:00", "09:30", state: .locked)
        let due = DeterministicPlanner.plan(
            PlanningFixture.input(
                calendar: [], tasks: [dueItem], ideas: [], settings: settings(), previousBlocks: [dueHeld]))
        #expect(
            due.unscheduled.first { $0.subject == dueItem.subject }?.reason
                == "No free time is left before the deadline for the remaining 60 minutes")
    }

    @Test("A task that is not splittable stays exactly as the owner placed it")
    func unsplittableHeldTaskStaysAsPlaced() {
        let item = report(splittable: false)
        let held = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: .locked)
        let output = DeterministicPlanner.plan(
            PlanningFixture.input(calendar: [], tasks: [item], ideas: [], settings: settings(), previousBlocks: [held]))
        #expect(blocks(of: item, in: output) == [held])
        #expect(output.unscheduled.isEmpty)
    }

    @Test("New parts never reuse a held block's ID")
    func newPartsNeverReuseHeldIDs() {
        let item = report()
        let heldIDs = ["\(item.subject.key)#0", "\(item.subject.key)#2"]
        let held = [
            PlanningFixture.block(heldIDs[0], for: item, "09:00", "09:15", state: .locked),
            PlanningFixture.block(heldIDs[1], for: item, "09:30", "09:45", state: .completed),
        ]
        let input = PlanningFixture.input(
            calendar: [PlanningFixture.busy("busy-1", "10:00", "11:30")], tasks: [item], ideas: [],
            settings: settings(), previousBlocks: held)
        let output = DeterministicPlanner.plan(input)
        let added = blocks(of: item, in: output).filter { !held.contains($0) }
        #expect(added.count >= 2)
        #expect(Set(added.map(\.blockID)).isDisjoint(with: heldIDs))
        #expect(Set(added.map(\.blockID)).count == added.count)
        #expect(minutes(blocks(of: item, in: output)) == 90)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Moving a block locks it at the new time and keeps its identity")
    func moveLocksBlock() throws {
        let item = report(minutes: 30)
        let proposed = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: .proposed)
        let moved = try PlanBlockMove.moved(
            proposed, start: at("14:00"), end: at("14:45"), among: [proposed], calendar: [], on: PlanningFixture.date,
            in: zone.timeZone)
        #expect(moved.blockID == proposed.blockID)
        #expect(moved.subject == proposed.subject)
        #expect(moved.title == proposed.title)
        #expect(moved.state == .locked)
        #expect(!moved.provisional)
        #expect(local(moved) == "14:00–14:45")
        #expect(moved.explanation == PlanBlockMove.explanation)

        let replanned = DeterministicPlanner.plan(
            PlanningFixture.input(calendar: [], tasks: [item], ideas: [], settings: settings(), previousBlocks: [moved])
        )
        #expect(blocks(of: item, in: replanned) == [moved])
    }

    @Test("A move that breaks a hard constraint or leaves the day is refused")
    func movesAreRefused() {
        let date = PlanningFixture.date
        let tz = zone.timeZone
        let item = report(minutes: 30)
        let other = PlanningFixture.item(.task, id: "other", minutes: 30)
        let done = PlanningFixture.item(.task, id: "done", minutes: 30)
        let proposed = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: .proposed)
        let accepted = PlanningFixture.block("\(other.subject.key)#0", for: other, "11:00", "11:30", state: .accepted)
        let completed = PlanningFixture.block("\(done.subject.key)#0", for: done, "08:00", "08:30", state: .completed)
        let busy = PlanningFixture.busy("busy-1", "10:00", "11:00")
        let event = PlanBlock(
            blockID: "event:busy-1", kind: .fixedEvent, subject: .occurrence(busy.occurrenceID), title: busy.title,
            range: busy.range, state: .locked, provisional: false, explanation: "Calendar commitment")
        let blocks = [proposed, accepted, completed, event]
        func move(_ block: PlanBlock, _ start: Date, _ end: Date) throws(PlanBlockMoveRefusal) -> PlanBlock {
            try PlanBlockMove.moved(block, start: start, end: end, among: blocks, calendar: [busy], on: date, in: tz)
        }
        #expect(throws: PlanBlockMoveRefusal.calendarEvent) { try move(event, at("12:00"), at("13:00")) }
        #expect(throws: PlanBlockMoveRefusal.completed) { try move(completed, at("12:00"), at("12:30")) }
        #expect(throws: PlanBlockMoveRefusal.endNotAfterStart) { try move(proposed, at("09:30"), at("09:30")) }
        #expect(throws: PlanBlockMoveRefusal.endNotAfterStart) { try move(proposed, at("09:30"), at("09:00")) }
        #expect(throws: PlanBlockMoveRefusal.notWholeMinute(field: "start")) {
            try move(proposed, at("09:30:30"), at("10:00"))
        }
        #expect(throws: PlanBlockMoveRefusal.notWholeMinute(field: "end")) {
            try move(proposed, at("09:30"), at("09:59:30"))
        }
        #expect(throws: PlanBlockMoveRefusal.outsideDay(field: "start", date: "2026-11-16", zone: "America/New_York")) {
            try move(proposed, TestTime.instant("2026-11-15T23:30", in: TestTime.newYork), at("00:30"))
        }
        #expect(throws: PlanBlockMoveRefusal.outsideDay(field: "end", date: "2026-11-16", zone: "America/New_York")) {
            try move(proposed, at("23:30"), TestTime.instant("2026-11-17T00:30", in: TestTime.newYork))
        }
        #expect(throws: PlanBlockMoveRefusal.overlapsCalendarEvent(local: "10:00–11:00")) {
            try move(proposed, at("10:30"), at("11:30"))
        }
        #expect(throws: PlanBlockMoveRefusal.overlapsHeldBlock(state: .accepted, local: "11:00–11:30")) {
            try move(proposed, at("11:15"), at("11:45"))
        }
    }

    @Test("A move may end at the closing midnight, or go outside the planning windows, protected time or free entries")
    func ownerMayPlaceBlocksOutsideSuggestions() throws {
        let item = report(minutes: 30)
        let proposed = PlanningFixture.block("\(item.subject.key)#0", for: item, "09:00", "09:30", state: .proposed)
        let free = PlanningFixture.busy("free-1", "12:00", "13:00", blocksTime: false)
        let other = PlanningFixture.item(.task, id: "other", minutes: 30)
        let suggestion = PlanningFixture.block("\(other.subject.key)#0", for: other, "07:00", "07:30", state: .proposed)
        let midnight = TestTime.instant("2026-11-17T00:00", in: TestTime.newYork)
        let cases: [(Date, Date, String)] = [
            (at("23:30"), midnight, "23:30–00:00"), (at("12:00"), at("12:30"), "12:00–12:30"),
            (at("07:00"), at("07:30"), "07:00–07:30"),
        ]
        for (start, end, expected) in cases {
            let moved = try PlanBlockMove.moved(
                proposed, start: start, end: end, among: [proposed, suggestion], calendar: [free],
                on: PlanningFixture.date, in: zone.timeZone)
            #expect(local(moved) == expected)
        }
    }
}
