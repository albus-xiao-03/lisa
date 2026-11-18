// Test-only. Fixed zones, local dates, times, instants and clocks built through the production LisaTime types, so no
// test reads the wall clock or the machine's zone (DATA-03; spec §16 "deterministic"). Used by every suite.

import Foundation
import LisaTime
import Testing

/// Fixed time values for tests. Nothing here reads the system clock or the machine's time zone.
///
/// A malformed literal records a test issue (so the test fails visibly) instead of crashing the test process.
enum TestTime {
    /// America/New_York: the §16.2 zone. Daylight-saving time starts on 2026-03-08 and ends on 2026-11-01.
    static let newYork = zone("America/New_York")
    /// America/Los_Angeles, three hours behind New York all year.
    static let losAngeles = zone("America/Los_Angeles")
    /// America/Chicago, used as a configured floating-time zone.
    static let chicago = zone("America/Chicago")
    /// Asia/Tokyo, which keeps one offset all year.
    static let tokyo = zone("Asia/Tokyo")

    /// A validated IANA zone.
    static func zone(_ identifier: String) -> TimeZoneID {
        if let zone = TimeZoneID(identifier) { return zone }
        Issue.record("the test zone \(identifier) is not in the system time-zone database")
        return .utc
    }

    /// The local date written `YYYY-MM-DD`.
    static func date(_ iso: String) -> LocalDate {
        if let date = LocalDate(iso: iso) { return date }
        Issue.record("not a YYYY-MM-DD date: \(iso)")
        return LocalDate(daysSinceEpoch: 0)
    }

    /// The time of day written `HH:MM` or `HH:MM:SS`.
    static func time(_ iso: String) -> LocalTime {
        if let time = LocalTime(iso: iso) { return time }
        Issue.record("not an HH:MM[:SS] time: \(iso)")
        return .midnight
    }

    /// The floating date-time written `YYYY-MM-DDTHH:MM[:SS]`.
    static func local(_ iso: String) -> LocalDateTime {
        if let value = LocalDateTime(iso: iso) { return value }
        Issue.record("not a YYYY-MM-DDTHH:MM[:SS] date-time: \(iso)")
        return LocalDateTime(secondsSinceEpoch: 0)
    }

    /// The UTC instant written `YYYY-MM-DDTHH:MM[:SS]`, computed by plain arithmetic rather than zone rules, so it can
    /// serve as an independent expectation for zone conversions.
    static func utcInstant(_ iso: String) -> Date {
        Date(millisecondsSince1970: Int64(local(iso).secondsSinceEpoch) * 1000)
    }

    /// The instant of local date-time `iso` in `zone`, through the production zone rules: the earlier instant in a
    /// fall-back overlap unless `preferLater`, and the RFC 5545 shifted instant in a spring-forward gap (D-03).
    static func instant(_ iso: String, in zone: TimeZoneID, preferLater: Bool = false) -> Date {
        ZoneRules.instant(for: local(iso), in: zone.timeZone, preferLater: preferLater)
    }

    /// The instants from local `start` to local `end` (times of day `HH:MM`) on `date` in `zone`.
    static func range(_ start: String, _ end: String, on date: String, in zone: TimeZoneID) -> TimeRange {
        TimeRange(
            uncheckedStart: instant("\(date)T\(start)", in: zone), end: instant("\(date)T\(end)", in: zone))
    }

    /// The local time of day of `instant` in `zone`, as `HH:MM` (or `HH:MM:SS`).
    static func localTime(of instant: Date, in zone: TimeZoneID) -> String {
        ZoneRules.local(for: instant, in: zone.timeZone).time.iso
    }

    /// A settable clock fixed at `instant`; it moves only when the test moves it.
    static func clock(at instant: Date) -> ManualWallClock {
        ManualWallClock(instant)
    }
}
