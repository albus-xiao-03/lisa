// Test-only. Checks a planner output against the PLAN-02 hard constraints without using the planner itself (L11,
// §16.2, §16.3; later replanning tests, L12).

import Foundation
import LisaDomain
import LisaPlanning
import LisaTime

/// Lists every way a plan breaks a hard constraint. An empty list means the plan respects them all.
enum PlanConstraintCheck {
    /// Every proposed block must avoid busy events (widened by the configured buffer), protected time and every other
    /// block; it must lie inside the planning windows, end by its item's deadline and not start before `now`.
    static func violations(of output: PlanningOutput, for input: PlanningInput) -> [String] {
        let zone = input.zone.timeZone
        let buffer = TimeInterval(input.settings.bufferMinutes * 60)
        let busy = input.calendar.filter(\.blocksTime).map {
            TimeRange(
                uncheckedStart: $0.range.start.addingTimeInterval(-buffer), end: $0.range.end.addingTimeInterval(buffer)
            )
        }
        let windows = IntervalSet(input.settings.windows.compactMap { $0.range(on: input.date, in: zone) })
        let protected = input.settings.protectedTime.compactMap { $0.range(on: input.date, in: zone) }
        var deadlines: [String: Deadline] = [:]
        for item in input.tasks + input.ideas {
            if let deadline = item.deadline { deadlines[item.subject.key] = deadline }
        }
        let held = output.blocks.filter { $0.kind != .fixedEvent }
        var problems: [String] = []
        for block in held where block.state == .proposed {
            let name = "\(block.blockID) at \(describe(block.range, in: zone))"
            if busy.contains(where: { $0.overlaps(block.range) }) {
                problems.append("\(name) overlaps a busy event or its buffer")
            }
            if protected.contains(where: { $0.overlaps(block.range) }) {
                problems.append("\(name) overlaps protected time")
            }
            if held.contains(where: { $0.blockID != block.blockID && $0.range.overlaps(block.range) }) {
                problems.append("\(name) overlaps another block")
            }
            if !windows.ranges.contains(where: { $0.contains(block.range) }) {
                problems.append("\(name) is outside the planning windows")
            }
            if let deadline = deadlines[block.subject.key], block.range.end > deadline.latestInstant(in: zone) {
                problems.append("\(name) ends after its deadline")
            }
            if block.range.start < input.now {
                problems.append("\(name) starts before now")
            }
        }
        return problems
    }

    /// `range` as local `HH:MM–HH:MM` in `zone`.
    static func describe(_ range: TimeRange, in zone: TimeZone) -> String {
        let start = ZoneRules.local(for: range.start, in: zone).time.iso
        let end = ZoneRules.local(for: range.end, in: zone).time.iso
        return "\(start)–\(end)"
    }
}
