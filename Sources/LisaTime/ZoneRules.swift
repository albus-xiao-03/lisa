// Conversions between instants and local date-times, with explicit daylight-saving gap and overlap handling.

import Foundation

/// How a local date-time maps onto instants in a particular time zone.
public enum LocalTimeResolution: Hashable, Sendable {
    /// Exactly one instant has this local time.
    case exact(Date)
    /// The local time does not exist (a spring-forward gap). `shifted` applies the offset in force before the gap,
    /// as RFC 5545 prescribes, which moves the time later by the gap length.
    case gap(shifted: Date, gapSeconds: Int)
    /// The local time occurs twice (a fall-back overlap).
    case overlap(earlier: Date, later: Date)
}

/// Time-zone arithmetic that does not depend on platform calendar quirks.
public enum ZoneRules {
    /// Resolves `local` in `zone`, reporting gaps and overlaps explicitly.
    public static func resolve(_ local: LocalDateTime, in zone: TimeZone) -> LocalTimeResolution {
        resolve(local, rules: zone)
    }

    /// The instant for `local` in `zone`: the earlier instant in an overlap (unless `preferLater`), and the
    /// RFC 5545 shifted instant in a gap.
    public static func instant(for local: LocalDateTime, in zone: TimeZone, preferLater: Bool = false) -> Date {
        switch resolve(local, in: zone) {
        case .exact(let date): date
        case .gap(let shifted, _): shifted
        case .overlap(let earlier, let later): preferLater ? later : earlier
        }
    }

    /// The local date-time of `instant` in `zone`, truncated to whole seconds.
    public static func local(for instant: Date, in zone: TimeZone) -> LocalDateTime {
        let offset = zone.secondsFromGMT(for: instant)
        let seconds = Int((instant.timeIntervalSince1970).rounded(.down)) + offset
        return LocalDateTime(secondsSinceEpoch: seconds)
    }

    /// The local calendar date of `instant` in `zone`.
    public static func localDate(for instant: Date, in zone: TimeZone) -> LocalDate {
        local(for: instant, in: zone).date
    }

    /// The first instant of `date` in `zone` (midnight, or the first valid time after a midnight gap).
    public static func startOfDay(_ date: LocalDate, in zone: TimeZone) -> Date {
        instant(for: LocalDateTime(date: date, time: .midnight), in: zone)
    }

    /// The instants covered by `date` in `zone`; 23, 24 or 25 hours long around daylight-saving changes.
    public static func dayRange(_ date: LocalDate, in zone: TimeZone) -> TimeRange {
        let start = startOfDay(date, in: zone)
        let end = startOfDay(date.adding(days: 1), in: zone)
        return TimeRange(uncheckedStart: start, end: max(end, start))
    }
}
