// Test-only. Checks a stored plan against the stored calendar without using the planner: a proposed block must never
// overlap an occurrence that blocks time (PLAN-02, CAL-02). Used by the service-level planning suites (L07, L12,
// §16.2 at service level, §16.3).

import Foundation
import LisaDomain
import LisaTime

/// Plan checks over stored records.
enum StoredPlanCheck {
    /// Each proposed block that overlaps an occurrence blocking time, as `"<block> HH:MM–HH:MM overlaps <event>"`.
    static func overlaps(in plan: Plan, with occurrences: [CalendarOccurrence], zone: TimeZoneID) -> [String] {
        let busy = occurrences.filter(\.blocksTime)
        var problems: [String] = []
        for block in plan.blocks where block.kind != .fixedEvent && block.state == .proposed {
            for event in busy where event.range(in: zone.timeZone).overlaps(block.range) {
                let times = PlanConstraintCheck.describe(block.range, in: zone.timeZone)
                problems.append("\(block.title) \(times) overlaps \(event.title)")
            }
        }
        return problems
    }

    /// The local `HH:MM–HH:MM` times of the plan's blocks for `subject`, in plan order.
    static func times(of subject: PlanSubject, in plan: Plan, zone: TimeZoneID) -> [String] {
        plan.blocks.filter { $0.subject == subject }.map { PlanConstraintCheck.describe($0.range, in: zone.timeZone) }
    }
}
