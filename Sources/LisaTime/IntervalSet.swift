// A normalized set of disjoint time ranges, used for busy and free time.

import Foundation

/// A set of instants represented as sorted, disjoint, non-touching ranges.
public struct IntervalSet: Hashable, Sendable {
    /// The normalized ranges in ascending order.
    public private(set) var ranges: [TimeRange]

    public init(_ ranges: [TimeRange] = []) {
        self.ranges = IntervalSet.normalize(ranges)
    }

    /// Whether the set covers no instant.
    public var isEmpty: Bool { ranges.isEmpty }

    /// Total covered seconds.
    public var totalDuration: TimeInterval { ranges.reduce(0) { $0 + $1.duration } }

    /// Adds `range` to the set.
    public mutating func insert(_ range: TimeRange) {
        ranges = IntervalSet.normalize(ranges + [range])
    }

    /// The union with another set.
    public func union(_ other: IntervalSet) -> IntervalSet {
        IntervalSet(ranges + other.ranges)
    }

    /// Whether any range in the set overlaps `range`.
    public func overlaps(_ range: TimeRange) -> Bool {
        ranges.contains { $0.overlaps(range) }
    }

    /// The parts of `window` not covered by this set.
    public func gaps(in window: TimeRange) -> [TimeRange] {
        var result: [TimeRange] = []
        var cursor = window.start
        for range in ranges where range.end > window.start && range.start < window.end {
            if range.start > cursor {
                result.append(TimeRange(uncheckedStart: cursor, end: min(range.start, window.end)))
            }
            cursor = max(cursor, range.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            result.append(TimeRange(uncheckedStart: cursor, end: window.end))
        }
        return result.filter { !$0.isEmpty }
    }

    /// This set with every instant of `other` removed.
    public func subtracting(_ other: IntervalSet) -> IntervalSet {
        var result: [TimeRange] = []
        for range in ranges {
            result.append(contentsOf: other.gaps(in: range))
        }
        return IntervalSet(result)
    }

    private static func normalize(_ input: [TimeRange]) -> [TimeRange] {
        let sorted = input.filter { !$0.isEmpty }.sorted()
        var merged: [TimeRange] = []
        for range in sorted {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = TimeRange(uncheckedStart: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
