// The new start and end the owner picks to move a block of the rundown (PLAN-04).

import Foundation
import LisaAPIContract

/// A block's new times, as the owner picked them to move it (`RundownModel.move(_:to:)`).
///
/// Any two instants can be held, so times whose end is not after their start are refused with a reason instead of
/// stopping the app, as building a `DateInterval` from them would.
public struct PlanBlockTimes: Hashable, Sendable {
    /// The new start.
    public var start: Date
    /// The new end.
    public var end: Date

    /// Times from `start` to `end`.
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// The times `block` has now, where pickers for moving it start.
    public init(of block: PlanBlockDTO) {
        self.init(start: block.start, end: block.end)
    }

    /// The times to the minute, as time pickers show them: seconds and fractions of a second are dropped.
    public var toTheMinute: PlanBlockTimes {
        PlanBlockTimes(start: Self.minute(of: start), end: Self.minute(of: end))
    }

    /// Whether the end is after the start, as a move needs.
    public var isOrdered: Bool { end > start }

    private static func minute(of instant: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (instant.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
