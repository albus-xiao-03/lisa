// The owner's move of a plan block to a new time (PLAN-04), checked against the hard constraints that still hold.

import Foundation
import LisaDomain
import LisaTime

/// Moves a block to the start and end the owner gives, on the plan's local day (PLAN-04).
///
/// The block keeps its identifier and subject and becomes `locked`: the planner keeps locked blocks exactly where they
/// are (D-15), so planning again keeps the block where the owner put it, even when a busy event later overlaps it.
/// The move is refused, and nothing changes, when:
/// - the block is a calendar event, or was completed;
/// - the end is not after the start, or either one is not a whole minute;
/// - either one is outside the plan's local day (a block may end at the midnight that ends the day);
/// - it would overlap a busy calendar occurrence (PLAN-02), or another block the owner holds: accepted, locked
///   (including moved blocks) or completed.
///
/// Planning windows, protected time and buffers shape Lisa's proposals only; the owner may place a block there.
/// Suggestions and declined or deferred blocks hold no time, so the planner places suggestions around the moved block.
public enum PlanBlockMove {
    /// What a moved block says about its time.
    public static let explanation = "You moved this block here; Lisa keeps it at this time when she plans again"

    /// `block` moved to `start`–`end`, or the reason it cannot move there.
    /// - Parameters:
    ///   - blocks: the plan's blocks, `block` among them.
    ///   - calendar: the calendar occurrences of the plan's day; only those that block time constrain the move.
    ///   - date: the plan's local date, in `zone`.
    public static func moved(
        _ block: PlanBlock, start: Date, end: Date, among blocks: [PlanBlock], calendar: [CalendarBlock],
        on date: LocalDate, in zone: TimeZone
    ) throws(PlanBlockMoveRefusal) -> PlanBlock {
        guard block.kind != .fixedEvent else { throw .calendarEvent }
        guard block.state != .completed else { throw .completed }
        guard end > start else { throw .endNotAfterStart }
        guard isWholeMinute(start) else { throw .notWholeMinute(field: "start") }
        guard isWholeMinute(end) else { throw .notWholeMinute(field: "end") }
        let day = ZoneRules.dayRange(date, in: zone)
        guard start >= day.start, start < day.end else {
            throw .outsideDay(field: "start", date: date.iso, zone: zone.identifier)
        }
        guard end <= day.end else { throw .outsideDay(field: "end", date: date.iso, zone: zone.identifier) }
        let range = TimeRange(uncheckedStart: start, end: end)
        let busy = calendar.filter { $0.blocksTime && $0.range.overlaps(range) }.map(\.range)
        if let event = busy.min() { throw .overlapsCalendarEvent(local: local(event, zone)) }
        let held = blocks.filter { other in
            other.blockID != block.blockID && other.kind != .fixedEvent && holdsTime(other.state)
                && other.range.overlaps(range)
        }
        if let other = held.min(by: { ($0.range, $0.blockID) < ($1.range, $1.blockID) }) {
            throw .overlapsHeldBlock(state: other.state, local: local(other.range, zone))
        }
        return PlanBlock(
            blockID: block.blockID, kind: block.kind, subject: block.subject, title: block.title, range: range,
            state: .locked, provisional: false, explanation: explanation)
    }

    /// Whether a block in `state` holds its time against a move: the owner accepted, locked or completed it.
    public static func holdsTime(_ state: PlanBlockState) -> Bool {
        switch state {
        case .accepted, .locked, .completed: true
        case .proposed, .rejected, .deferred: false
        }
    }

    private static func isWholeMinute(_ instant: Date) -> Bool {
        instant.millisecondsSince1970 % 60_000 == 0
    }

    /// `range` as local times of day in `zone`, such as `10:00–11:00`.
    private static func local(_ range: TimeRange, _ zone: TimeZone) -> String {
        let start = ZoneRules.local(for: range.start, in: zone).time
        let end = ZoneRules.local(for: range.end, in: zone).time
        return "\(start.iso)–\(end.iso)"
    }
}
