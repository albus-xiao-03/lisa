// Quiet hours in local time, which may wrap past midnight.

import Foundation
import LisaTime

/// A daily quiet period in local time, such as 22:00–07:00.
public struct QuietHours: Hashable, Codable, Sendable {
    public var start: LocalTime
    public var end: LocalTime

    public init(start: LocalTime, end: LocalTime) {
        self.start = start
        self.end = end
    }

    /// The R1 starting value: 22:00–07:00 (REM-02).
    public static let defaultValue = QuietHours(
        start: LocalTime(secondsSinceMidnight: 22 * 3600), end: LocalTime(secondsSinceMidnight: 7 * 3600))

    /// Whether `time` falls inside quiet hours.
    public func contains(_ time: LocalTime) -> Bool {
        if start == end { return false }
        if start < end { return start <= time && time < end }
        return time >= start || time < end
    }

    /// Whether `instant` falls inside quiet hours in `zone`.
    public func contains(_ instant: Date, in zone: TimeZone) -> Bool {
        contains(ZoneRules.local(for: instant, in: zone).time)
    }

    /// The first instant at or after `instant` that is outside quiet hours in `zone`.
    public func nextAllowedInstant(after instant: Date, in zone: TimeZone) -> Date {
        guard contains(instant, in: zone) else { return instant }
        let local = ZoneRules.local(for: instant, in: zone)
        var endDate = local.date
        if start > end, local.time >= start { endDate = endDate.adding(days: 1) }
        return ZoneRules.instant(for: LocalDateTime(date: endDate, time: end), in: zone)
    }
}
