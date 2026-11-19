// Why the owner's move of a plan block to a new time was refused (PLAN-04): a hard constraint or the plan's day.

/// A move of a plan block that would break a rule, with an owner-facing reason. The reason names times and states but
/// never a title or other private content. The API answers it as a validation failure (400) naming `field` when one
/// bound is at fault; nothing in the plan changes.
public enum PlanBlockMoveRefusal: Error, Hashable, Sendable, CustomStringConvertible {
    /// A calendar event is changed in the calendar, never in the plan.
    case calendarEvent
    /// A completed block records work already done.
    case completed
    /// The new end is not after the new start.
    case endNotAfterStart
    /// The new start or end (`field`) has seconds or a fraction of a second.
    case notWholeMinute(field: String)
    /// The new start or end (`field`) is not on the plan's local day `date` (`YYYY-MM-DD`) in `zone`.
    case outsideDay(field: String, date: String, zone: String)
    /// The new time overlaps a busy calendar event, which takes place at `local` (for example `10:00–11:00`).
    case overlapsCalendarEvent(local: String)
    /// The new time overlaps another block the owner holds (accepted, locked or completed) at `local`.
    case overlapsHeldBlock(state: PlanBlockState, local: String)
    /// The plan is for `date`, a day that has passed.
    case dayHasPassed(date: String)
    /// The plan was made in `zone`, which is no longer the owner's time zone.
    case otherTimeZone(zone: String)

    /// The request field at fault (`start` or `end`), or `nil` when the move as a whole is refused.
    public var field: String? {
        switch self {
        case .endNotAfterStart: "end"
        case .notWholeMinute(let field), .outsideDay(let field, _, _): field
        default: nil
        }
    }

    /// The reason, as one sentence for the owner.
    public var message: String {
        switch self {
        case .calendarEvent:
            "calendar events are changed in the calendar, not in the plan"
        case .completed:
            "a completed block can't be moved: it records work already done"
        case .endNotAfterStart:
            "the new end must be after the new start"
        case .notWholeMinute(let field):
            "the new \(field) must be a whole minute, without seconds"
        case .outsideDay(let field, let date, let zone):
            "the new \(field) must be on the rundown's day, \(date) in \(zone)"
        case .overlapsCalendarEvent(let local):
            "the new time overlaps a busy calendar event at \(local)"
        case .overlapsHeldBlock(let state, let local):
            "the new time overlaps \(Self.held(state)) at \(local)"
        case .dayHasPassed(let date):
            "the rundown for \(date) is for a day that has passed; blocks are moved on today's or a later rundown"
        case .otherTimeZone(let zone):
            "the rundown was planned in \(zone), which is no longer the owner's time zone; move the block on the "
                + "current rundown"
        }
    }

    public var description: String { message }

    private static func held(_ state: PlanBlockState) -> String {
        switch state {
        case .accepted: "a block that was accepted"
        case .completed: "a completed block"
        default: "a locked block"
        }
    }
}
