// A time of day without a date or time zone, with whole-second precision.

import Foundation

/// A wall-clock time of day such as 09:30, with no date and no time zone.
public struct LocalTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int
    public let second: Int

    /// Creates a time, or returns `nil` when a component is out of range.
    public init?(hour: Int, minute: Int, second: Int = 0) {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// Creates the time `seconds` seconds after midnight, wrapping at 24 hours.
    public init(secondsSinceMidnight seconds: Int) {
        let wrapped = ((seconds % 86_400) + 86_400) % 86_400
        hour = wrapped / 3600
        minute = wrapped % 3600 / 60
        second = wrapped % 60
    }

    /// Parses `HH:MM` or `HH:MM:SS`.
    public init?(iso text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts.allSatisfy({ $0.count == 2 }),
            let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return nil }
        let second = parts.count == 3 ? Int(parts[2]) : 0
        guard let second else { return nil }
        self.init(hour: hour, minute: minute, second: second)
    }

    /// Midnight, 00:00:00.
    public static let midnight = LocalTime(secondsSinceMidnight: 0)

    /// Seconds elapsed since midnight.
    public var secondsSinceMidnight: Int {
        hour * 3600 + minute * 60 + second
    }

    /// The text form `HH:MM`, or `HH:MM:SS` when seconds are present.
    public var iso: String {
        second == 0
            ? String(format: "%02d:%02d", hour, minute)
            : String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    public var description: String { iso }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.secondsSinceMidnight < rhs.secondsSinceMidnight
    }
}

extension LocalTime: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let time = LocalTime(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected HH:MM or HH:MM:SS")
        }
        self = time
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
