// A half-open interval of instants, [start, end).

import Foundation

/// A half-open interval of instants `[start, end)`.
public struct TimeRange: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let start: Date
    public let end: Date

    /// Creates a range, or returns `nil` when `end` is before `start`.
    public init?(start: Date, end: Date) {
        guard end >= start else { return nil }
        self.start = start
        self.end = end
    }

    /// Creates a range whose bounds the caller has already ordered.
    public init(uncheckedStart start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Creates a range starting at `start` and lasting `seconds`.
    public init(start: Date, duration seconds: TimeInterval) {
        self.start = start
        self.end = start.addingTimeInterval(max(0, seconds))
    }

    /// Length in seconds.
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public var isEmpty: Bool { end <= start }

    /// Whether the two ranges share any instant. Touching ranges do not overlap.
    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    /// Whether `instant` lies inside the range.
    public func contains(_ instant: Date) -> Bool {
        start <= instant && instant < end
    }

    /// Whether `other` lies entirely inside this range.
    public func contains(_ other: TimeRange) -> Bool {
        start <= other.start && other.end <= end
    }

    /// The shared part of two ranges, if any.
    public func intersection(_ other: TimeRange) -> TimeRange? {
        let lower = max(start, other.start)
        let upper = min(end, other.end)
        return upper > lower ? TimeRange(uncheckedStart: lower, end: upper) : nil
    }

    public var description: String {
        "[\(start.millisecondsSince1970)ms, \(end.millisecondsSince1970)ms)"
    }

    public static func < (lhs: TimeRange, rhs: TimeRange) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }
}
