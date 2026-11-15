// RRULE parsing for the supported subset; parts outside it are recorded so callers can warn and act conservatively.

import Foundation
import LisaTime

/// A parsed recurrence rule.
public struct RecurrenceRule: Hashable, Sendable {
    public enum Frequency: String, Sendable {
        case secondly = "SECONDLY"
        case minutely = "MINUTELY"
        case hourly = "HOURLY"
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    /// A BYDAY entry such as `MO`, `2TU` or `-1FR`.
    public struct WeekdayEntry: Hashable, Sendable {
        public let ordinal: Int?
        public let weekday: Weekday
    }

    public var frequency: Frequency
    public var interval: Int
    public var count: Int?
    public var until: TimeValue?
    public var byDay: [WeekdayEntry]
    public var byMonthDay: [Int]
    public var byMonth: [Int]
    public var bySetPosition: [Int]
    public var weekStart: Weekday
    /// Rule parts or values outside the supported subset (for example BYHOUR or FREQ=HOURLY).
    public var unsupported: [String]

    /// Whether the rule can be expanded faithfully.
    public var isSupported: Bool { unsupported.isEmpty }

    /// Parses an RRULE value such as `FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10`.
    public static func parse(_ text: String) -> RecurrenceRule? {
        var rule = RecurrenceRule(
            frequency: .daily, interval: 1, count: nil, until: nil, byDay: [], byMonthDay: [], byMonth: [],
            bySetPosition: [], weekStart: .monday, unsupported: [])
        var sawFrequency = false
        for part in text.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].uppercased()
            let value = pieces[1]
            switch key {
            case "FREQ":
                guard let frequency = Frequency(rawValue: value.uppercased()) else { return nil }
                rule.frequency = frequency
                sawFrequency = true
                if [.secondly, .minutely, .hourly].contains(frequency) {
                    rule.unsupported.append("FREQ=\(frequency.rawValue)")
                }
            case "INTERVAL":
                guard let interval = Int(value), interval >= 1 else { return nil }
                rule.interval = interval
            case "COUNT":
                guard let count = Int(value), count >= 1 else { return nil }
                rule.count = count
            case "UNTIL":
                rule.until = ICalValues.timeValue(value, valueType: nil, tzid: nil)
                if rule.until == nil { return nil }
            case "BYDAY":
                for entry in value.split(separator: ",") {
                    guard let parsed = parseWeekdayEntry(String(entry)) else { return nil }
                    rule.byDay.append(parsed)
                }
            case "BYMONTHDAY":
                for entry in value.split(separator: ",") {
                    guard let day = Int(entry), day != 0, (-31...31).contains(day) else { return nil }
                    rule.byMonthDay.append(day)
                }
            case "BYMONTH":
                for entry in value.split(separator: ",") {
                    guard let month = Int(entry), (1...12).contains(month) else { return nil }
                    rule.byMonth.append(month)
                }
            case "BYSETPOS":
                for entry in value.split(separator: ",") {
                    guard let position = Int(entry), position != 0, (-366...366).contains(position) else { return nil }
                    rule.bySetPosition.append(position)
                }
            case "WKST":
                guard let weekday = Weekday(iCalendarCode: value) else { return nil }
                rule.weekStart = weekday
            default:
                rule.unsupported.append(key)
            }
        }
        guard sawFrequency else { return nil }
        if rule.frequency == .daily || rule.frequency == .weekly, rule.byDay.contains(where: { $0.ordinal != nil }) {
            rule.unsupported.append("BYDAY ordinals with FREQ=\(rule.frequency.rawValue)")
        }
        if rule.frequency == .weekly, !rule.byMonthDay.isEmpty {
            rule.unsupported.append("BYMONTHDAY with FREQ=WEEKLY")
        }
        return rule
    }

    private static func parseWeekdayEntry(_ text: String) -> WeekdayEntry? {
        guard text.count >= 2 else { return nil }
        let code = String(text.suffix(2))
        guard let weekday = Weekday(iCalendarCode: code) else { return nil }
        let prefix = text.dropLast(2)
        if prefix.isEmpty { return WeekdayEntry(ordinal: nil, weekday: weekday) }
        guard let ordinal = Int(prefix), ordinal != 0, (-53...53).contains(ordinal) else { return nil }
        return WeekdayEntry(ordinal: ordinal, weekday: weekday)
    }
}
