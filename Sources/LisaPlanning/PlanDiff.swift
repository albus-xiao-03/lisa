// Explains what changed between two plan revisions (PLAN-04: identify changes and affected proposals).

import Foundation
import LisaDomain
import LisaTime

/// Describes differences between plan revisions in owner-facing language.
public enum PlanDiff {
    public static func explain(previous: [PlanBlock], current: [PlanBlock], zone: TimeZone) -> [String] {
        let before = Dictionary(previous.map { ($0.subject.key, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.map { ($0.subject.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [String] = []
        for block in current where block.kind == .fixedEvent && before[block.subject.key] == nil {
            changes.append("New calendar commitment \"\(block.title)\" at \(format(block.range, zone))")
        }
        for block in previous where block.kind == .fixedEvent && after[block.subject.key] == nil {
            changes.append("\"\(block.title)\" is no longer on the calendar")
        }
        for block in current where block.kind != .fixedEvent {
            if let old = before[block.subject.key], old.range != block.range {
                changes.append(
                    "Moved \"\(block.title)\" from \(format(old.range, zone)) to \(format(block.range, zone))")
            }
        }
        for block in previous where block.kind != .fixedEvent && after[block.subject.key] == nil {
            changes.append("\"\(block.title)\" no longer fits and is listed as unscheduled")
        }
        return changes
    }

    static func format(_ range: TimeRange, _ zone: TimeZone) -> String {
        let start = ZoneRules.local(for: range.start, in: zone).time
        let end = ZoneRules.local(for: range.end, in: zone).time
        return "\(start.iso)–\(end.iso)"
    }
}
