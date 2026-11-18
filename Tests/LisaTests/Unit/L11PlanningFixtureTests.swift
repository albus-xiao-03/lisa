// Unit tests for L11 with the R1 §16.2 concrete planning fixture, exactly as the specification states it (PLAN-02,
// PLAN-03; D-15): the baseline plan, the plan after the added 09:00–09:30 event, its explained changes (PLAN-04), and
// no proposed block overlapping a busy event.

import Foundation
import LisaDomain
import LisaPlanning
import LisaTime
import Testing

@Suite("L11 — Planning: the §16.2 concrete fixture", .tags(.unit))
struct L11PlanningFixtureTests {
    private func local(_ block: PlanBlock) -> String {
        PlanConstraintCheck.describe(block.range, in: PlanningFixture.zone.timeZone)
    }

    private func times(of item: PlanningItem, in output: PlanningOutput) -> [String] {
        output.blocks.filter { $0.subject == item.subject }.map(local)
    }

    private func eventTimes(in output: PlanningOutput) -> [String] {
        output.blocks.filter { $0.kind == .fixedEvent }.map(local)
    }

    @Test("Baseline: the task is 09:00–09:30, the idea 09:30–10:00, and the event stays 10:00–11:00")
    func baseline() {
        let input = PlanningFixture.input(calendar: [PlanningFixture.busyEvent])
        let output = DeterministicPlanner.plan(input)
        #expect(times(of: PlanningFixture.task, in: output) == ["09:00–09:30"])
        #expect(times(of: PlanningFixture.idea, in: output) == ["09:30–10:00"])
        #expect(eventTimes(in: output) == ["10:00–11:00"])
        #expect(output.blocks.count == 3)
        #expect(output.unscheduled.isEmpty)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])

        let event = output.blocks.first { $0.kind == .fixedEvent }
        #expect(event?.subject == .occurrence(PlanningFixture.busyEvent.occurrenceID))
        #expect(event?.state == .locked)
        let task = output.blocks.first { $0.subject == PlanningFixture.task.subject }
        #expect(task?.kind == .task)
        #expect(task?.state == .proposed)
        #expect(task?.provisional == false)
        let idea = output.blocks.first { $0.subject == PlanningFixture.idea.subject }
        #expect(idea?.kind == .idea)
    }

    @Test("After the 09:00–09:30 event is added, the task moves to 09:30–10:00 and the idea to 11:00–11:30")
    func addedEvent() {
        let baseline = DeterministicPlanner.plan(PlanningFixture.input(calendar: [PlanningFixture.busyEvent]))
        let input = PlanningFixture.input(
            calendar: [PlanningFixture.busyEvent, PlanningFixture.addedEvent], previousBlocks: baseline.blocks)
        let output = DeterministicPlanner.plan(input)
        #expect(times(of: PlanningFixture.task, in: output) == ["09:30–10:00"])
        #expect(times(of: PlanningFixture.idea, in: output) == ["11:00–11:30"])
        #expect(eventTimes(in: output) == ["09:00–09:30", "10:00–11:00"])
        #expect(output.unscheduled.isEmpty)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("The change is explained: the new commitment and both moved proposals are named")
    func addedEventIsExplained() {
        let baseline = DeterministicPlanner.plan(PlanningFixture.input(calendar: [PlanningFixture.busyEvent]))
        let replanned = DeterministicPlanner.plan(
            PlanningFixture.input(calendar: [PlanningFixture.busyEvent, PlanningFixture.addedEvent]))
        let changes = PlanDiff.explain(
            previous: baseline.blocks, current: replanned.blocks, zone: PlanningFixture.zone.timeZone)
        #expect(changes.contains("New calendar commitment \"Fixture added event\" at 09:00–09:30"))
        #expect(changes.contains("Moved \"Fixture task\" from 09:00–09:30 to 09:30–10:00"))
        #expect(changes.contains("Moved \"Fixture idea\" from 09:30–10:00 to 11:00–11:30"))
        #expect(changes.count == 3)
    }

    @Test("With no allocation cap at all, the fixture produces the same two plans")
    func sameResultWithoutAllocationCap() {
        var settings = PlanningFixture.settings
        settings.maximumAllocation = 1
        let baseline = DeterministicPlanner.plan(
            PlanningFixture.input(calendar: [PlanningFixture.busyEvent], settings: settings))
        #expect(times(of: PlanningFixture.task, in: baseline) == ["09:00–09:30"])
        #expect(times(of: PlanningFixture.idea, in: baseline) == ["09:30–10:00"])
        let added = DeterministicPlanner.plan(
            PlanningFixture.input(
                calendar: [PlanningFixture.busyEvent, PlanningFixture.addedEvent], settings: settings))
        #expect(times(of: PlanningFixture.task, in: added) == ["09:30–10:00"])
        #expect(times(of: PlanningFixture.idea, in: added) == ["11:00–11:30"])
    }

    @Test("When another explicit constraint leaves no valid slot, the idea is reported unscheduled, never overlapping")
    func ideaUnscheduledWhenAnotherConstraintPreventsIt() {
        var settings = PlanningFixture.settings
        settings.protectedTime = [LocalWindow(start: TestTime.time("11:00"), end: TestTime.time("12:00"))]
        // Only 30 free minutes remain, so the allocation cap is lifted to isolate the protected-time constraint.
        settings.maximumAllocation = 1
        let input = PlanningFixture.input(
            calendar: [PlanningFixture.busyEvent, PlanningFixture.addedEvent], settings: settings)
        let output = DeterministicPlanner.plan(input)
        #expect(times(of: PlanningFixture.task, in: output) == ["09:30–10:00"])
        #expect(times(of: PlanningFixture.idea, in: output) == [])
        #expect(output.unscheduled.map(\.subject) == [PlanningFixture.idea.subject])
        #expect(output.unscheduled.first?.reason.isEmpty == false)
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Planning the fixture twice gives identical plans")
    func fixtureIsDeterministic() {
        let input = PlanningFixture.input(calendar: [PlanningFixture.addedEvent, PlanningFixture.busyEvent])
        #expect(DeterministicPlanner.plan(input) == DeterministicPlanner.plan(input))
        let reordered = PlanningFixture.input(calendar: [PlanningFixture.busyEvent, PlanningFixture.addedEvent])
        #expect(DeterministicPlanner.plan(input) == DeterministicPlanner.plan(reordered))
    }
}
