// A date and time of day without a time zone ("floating" time).

import Foundation

/// A local date and time with no time zone, such as an iCalendar floating time or a planning-window boundary.
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let date: LocalDate
    public let time: LocalTime

    public init(date: LocalDate, time: LocalTime) {
        self.date = date
        self.time = time
    }

    /// Parses `YYYY-MM-DDTHH:MM[:SS]`.
    public init?(iso text: String) {
        let parts = text.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2, let date = LocalDate(iso: String(parts[0])),
            let time = LocalTime(iso: String(parts[1]))
        else { return nil }
        self.init(date: date, time: time)
    }

    /// Seconds since 1970-01-01T00:00:00 in this floating time scale (as if the zone were UTC).
    public var secondsSinceEpoch: Int {
        date.daysSinceEpoch * 86_400 + time.secondsSinceMidnight
    }

    /// Creates the floating date-time `seconds` seconds after 1970-01-01T00:00:00.
    public init(secondsSinceEpoch seconds: Int) {
        let days = Int((Double(seconds) / 86_400).rounded(.down))
        date = LocalDate(daysSinceEpoch: days)
        time = LocalTime(secondsSinceMidnight: seconds - days * 86_400)
    }

    /// The date-time `seconds` seconds later in floating time.
    public func adding(seconds: Int) -> LocalDateTime {
        LocalDateTime(secondsSinceEpoch: secondsSinceEpoch + seconds)
    }

    public var iso: String { "\(date.iso)T\(time.iso)" }

    public var description: String { iso }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        lhs.secondsSinceEpoch < rhs.secondsSinceEpoch
    }
}

extension LocalDateTime: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = LocalDateTime(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DDTHH:MM[:SS]")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
