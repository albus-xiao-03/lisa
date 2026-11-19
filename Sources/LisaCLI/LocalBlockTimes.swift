// The new times `lisa plan block move` takes: local times of day on the rundown's date, in the rundown's time zone.

import ArgumentParser
import Foundation

/// The `--start` and `--end` of `lisa plan block move`: `HH:MM` in 24-hour time, in the rundown's time zone (the
/// owner's), on the rundown's date. `--end 24:00` is the midnight that ends the day.
///
/// On a day when the clocks change, a time the clocks skip is refused, and a time that occurs twice is its first
/// occurrence, as for every local time in Lisa (D-03).
struct LocalBlockTimes {
    /// Minutes after the start of the day: `--start` from 00:00 to 23:59.
    let start: Int
    /// Minutes after the start of the day: `--end` from 00:01 to 24:00, after `--start`.
    let end: Int

    /// The times, or a usage error naming the option at fault.
    init(start: String, end: String) throws {
        guard let first = Self.minutes(start), first < Self.minutesPerDay else {
            throw ValidationError("--start must be a time of day such as 09:30 (HH:MM, 24-hour)")
        }
        guard let last = Self.minutes(end) else {
            throw ValidationError("--end must be a time of day such as 10:15 (HH:MM, 24-hour; 24:00 is midnight)")
        }
        guard last > first else { throw ValidationError("--end must be after --start") }
        self.start = first
        self.end = last
    }

    /// The two times as instants on `date` (`YYYY-MM-DD`) in the time zone `zone`, or a usage error when one of them
    /// does not exist there.
    func instants(on date: String, in zone: String) throws -> (start: Date, end: Date) {
        guard let timeZone = TimeZone(identifier: zone) else {
            throw ValidationError("the rundown's time zone \(zone) is unknown here")
        }
        guard let day = Self.floatingMidnight(date) else {
            throw ValidationError("the rundown's date \(date) is not a calendar date")
        }
        return (
            try Self.instant(day, minutes: start, timeZone, option: "--start", date: date),
            try Self.instant(day, minutes: end, timeZone, option: "--end", date: date)
        )
    }

    // MARK: - Parsing and zone arithmetic

    private static let minutesPerDay = 24 * 60

    /// Minutes after midnight for `HH:MM`, 00:00 to 24:00.
    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy(isTwoDigits), let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...59).contains(minute)
        else { return nil }
        let total = hour * 60 + minute
        return (0...minutesPerDay).contains(total) ? total : nil
    }

    private static func isTwoDigits(_ part: Substring) -> Bool {
        part.count == 2 && part.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Midnight of `date` as if the time zone were UTC: the floating time scale local times are counted in.
    private static func floatingMidnight(_ date: String) -> Date? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The instant whose local time in `zone` is `minutes` after the floating midnight `day`: the earlier one when the
    /// local time occurs twice, and a usage error when the clocks skip it.
    private static func instant(_ day: Date, minutes: Int, _ zone: TimeZone, option: String, date: String) throws
        -> Date
    {
        let floating = day.addingTimeInterval(TimeInterval(minutes * 60))
        // A zone's offset changes at most once within a day around any local time, so the offsets in force a day
        // before and a day after, and at the time itself, are the only candidates.
        let probes = [-86_400.0, 0, 86_400].map { floating.addingTimeInterval($0) }
        let candidates = Set(probes.map { zone.secondsFromGMT(for: $0) }).compactMap { offset -> Date? in
            let instant = floating.addingTimeInterval(TimeInterval(-offset))
            return zone.secondsFromGMT(for: instant) == offset ? instant : nil
        }
        guard let earliest = candidates.min() else {
            let text = String(format: "%02d:%02d", minutes / 60, minutes % 60)
            throw ValidationError(
                "\(option) \(text) does not exist on \(date) in \(zone.identifier): the clocks skip it")
        }
        return earliest
    }
}
