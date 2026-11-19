// The device's local calendar date as `YYYY-MM-DD`, to tell a cached copy of an earlier day from today's and to step
// from one day to the next.

import Foundation

/// Local calendar dates in the API's `YYYY-MM-DD` form.
enum LocalDay {
    /// The date of `instant` in `zone`, such as `2026-11-16`.
    static func string(for instant: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Whether `date` (`YYYY-MM-DD`) is before the date of `instant` in `zone`. Dates in this form sort as text.
    static func isBefore(_ date: String, dayOf instant: Date, in zone: TimeZone) -> Bool {
        date < string(for: instant, in: zone)
    }

    /// The date `days` days after `date` (`YYYY-MM-DD`; negative for earlier days), or `nil` when `date` is not such a
    /// calendar date.
    static func adding(_ days: Int, to date: String) -> String? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            string(for: start, in: utc) == date, let moved = calendar.date(byAdding: .day, value: days, to: start)
        else { return nil }
        return string(for: moved, in: utc)
    }

    /// `date` (`YYYY-MM-DD`) as English words for speech, such as "November 16"; the text unchanged when it is not
    /// such a date.
    static func spokenEnglish(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month) else {
            return date
        }
        return "\(monthNames[month - 1]) \(day)"
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December",
    ]
}
