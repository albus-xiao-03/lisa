// Deadlines that keep timed instants and date-only meanings distinct.

import Foundation

/// When something is due. A date-only deadline never becomes an invented exact time.
public enum Deadline: Hashable, Codable, Sendable {
    /// Due at an exact instant. `zone` preserves the source time zone when known.
    case at(instant: Date, zone: TimeZoneID?)
    /// Due on a local calendar date, with no time of day.
    case onDate(LocalDate)

    /// Whether the deadline has a time of day.
    public var isTimed: Bool {
        if case .at = self { true } else { false }
    }

    /// The instant by which the deadline must be met when planning in `zone`.
    ///
    /// For a date-only deadline this is the end of that local day; it is used only as a planning boundary and
    /// is never shown or stored as the deadline itself.
    public func latestInstant(in zone: TimeZone) -> Date {
        switch self {
        case .at(let instant, _): instant
        case .onDate(let date): ZoneRules.startOfDay(date.adding(days: 1), in: zone)
        }
    }

    /// The local date on which the deadline falls in `zone`.
    public func localDate(in zone: TimeZone) -> LocalDate {
        switch self {
        case .at(let instant, _): ZoneRules.localDate(for: instant, in: zone)
        case .onDate(let date): date
        }
    }
}
