// A calendar date without a time of day or time zone (proleptic Gregorian).

import Foundation

/// A calendar date such as 2026-11-16, with no time of day and no time zone.
///
/// Date-only deadlines and all-day events use this type so that they are never silently turned into invented instants.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a date, or returns `nil` when the components do not name a real date between years 1 and 9999.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
            day >= 1, day <= LocalDate.daysInMonth(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Creates the date that is `daysSinceEpoch` days after 1970-01-01.
    public init(daysSinceEpoch: Int) {
        // Civil-from-days conversion (Howard Hinnant's algorithm).
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let resolvedDay = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let resolvedMonth = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
        year = yearOfEra + era * 400 + (resolvedMonth <= 2 ? 1 : 0)
        month = resolvedMonth
        day = resolvedDay
    }

    /// Parses an ISO 8601 calendar date of the form `YYYY-MM-DD`.
    public init?(iso text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The number of days between 1970-01-01 and this date.
    public var daysSinceEpoch: Int {
        // Days-from-civil conversion (Howard Hinnant's algorithm).
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthPrime = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The ISO 8601 text form, such as `2026-11-16`.
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    /// The day of the week.
    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        let index = ((daysSinceEpoch % 7) + 7 + 3) % 7
        return Weekday(rawValue: index + 1) ?? .monday
    }

    /// The date `days` days later (or earlier when negative).
    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// The number of days from this date to `other`.
    public func days(until other: LocalDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// The same day of the month `months` months later, or `nil` when that month has no such day.
    public func adding(months: Int) -> LocalDate? {
        let total = (year * 12 + (month - 1)) + months
        return LocalDate(year: total / 12, month: total % 12 + 1, day: day)
    }

    /// The first day of this date's month.
    public var startOfMonth: LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch - (day - 1))
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Whether `year` is a leap year in the Gregorian calendar.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// The number of days in `month` of `year`.
    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a YYYY-MM-DD date")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
