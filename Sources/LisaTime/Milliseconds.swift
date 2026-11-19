// Millisecond conversions that make stored instants round-trip exactly and compare equal.

import Foundation

extension Date {
    /// Milliseconds between 1970-01-01 and 2001-01-01, the reference date `Date` stores intervals from.
    private static let referenceOffsetMilliseconds: Int64 = 978_307_200_000

    /// Milliseconds since 1970-01-01T00:00:00Z, rounded to the nearest millisecond.
    public var millisecondsSince1970: Int64 {
        Int64((timeIntervalSinceReferenceDate * 1000).rounded()) + Date.referenceOffsetMilliseconds
    }

    /// Creates an instant from milliseconds since 1970-01-01T00:00:00Z.
    ///
    /// The value is built from `Date`'s own reference-date representation, so it is the nearest representable
    /// instant and compares equal to the same millisecond however else it was constructed.
    public init(millisecondsSince1970 milliseconds: Int64) {
        self.init(
            timeIntervalSinceReferenceDate: TimeInterval(milliseconds - Date.referenceOffsetMilliseconds) / 1000)
    }

    /// This instant rounded to whole milliseconds.
    public var roundedToMilliseconds: Date {
        Date(millisecondsSince1970: millisecondsSince1970)
    }
}
