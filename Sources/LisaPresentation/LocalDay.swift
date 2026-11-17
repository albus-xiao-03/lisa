// The device's local calendar date as `YYYY-MM-DD`, to tell a cached copy of an earlier day from today's.

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
