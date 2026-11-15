// A validated IANA time-zone identifier, used for planning, briefing and source-time semantics.

import Foundation

/// An IANA time-zone identifier such as `America/New_York`, validated against the system time-zone database.
public struct TimeZoneID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let identifier: String

    /// Creates the identifier, or returns `nil` when the system does not know the zone.
    public init?(_ identifier: String) {
        guard !identifier.isEmpty, identifier.count <= 64, TimeZone(identifier: identifier) != nil else { return nil }
        self.identifier = identifier
    }

    /// Coordinated Universal Time.
    public static let utc = TimeZoneID(validated: "UTC")

    private init(validated identifier: String) {
        self.identifier = identifier
    }

    /// The Foundation time zone. The identifier was validated at creation.
    public var timeZone: TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
    }

    public var description: String { identifier }

    public static func < (lhs: TimeZoneID, rhs: TimeZoneID) -> Bool {
        lhs.identifier < rhs.identifier
    }
}

extension TimeZoneID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let zone = TimeZoneID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown IANA time zone")
        }
        self = zone
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}
