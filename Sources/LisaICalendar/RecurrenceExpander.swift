// Bounded RRULE expansion in floating local time for DAILY, WEEKLY, MONTHLY and YEARLY rules.

import Foundation
import LisaTime

/// The result of expanding a rule.
public struct RecurrenceExpansion: Hashable, Sendable {
    /// Starts inside the requested window, in ascending order.
    public var starts: [LocalDateTime]
    /// True when a bound stopped the expansion before the rule was exhausted inside the window.
    public var truncated: Bool
}

/// Expands supported recurrence rules. Every loop is bounded by the horizon, COUNT/UNTIL and an iteration limit.
public enum RecurrenceExpander {
    /// Expands `rule` from `start`.
    ///
    /// - Parameters:
    ///   - windowStart: starts before this are counted for COUNT but not returned.
    ///   - horizon: expansion stops after this local date-time.
    ///   - isAfterUntil: whether a candidate start is past the rule's UNTIL bound.
    public static func expand(
        start: LocalDateTime, rule: RecurrenceRule, windowStart: LocalDateTime, horizon: LocalDateTime,
        isAfterUntil: (LocalDateTime) -> Bool, maxOccurrences: Int, maxIterations: Int
    ) -> RecurrenceExpansion {
        var state = State(
            start: start, rule: rule, windowStart: windowStart, horizon: horizon, maxOccurrences: maxOccurrences)
        var iterations = 0
        var periodIndex = 0
        while iterations < maxIterations {
            iterations += 1
            guard let period = periodStart(for: rule, start: start, index: periodIndex) else { break }
            if period > horizon.date { break }
            let candidates = applySetPositions(rule, candidates(for: rule, start: start, period: period))
            for date in candidates where !state.consider(LocalDateTime(date: date, time: start.time), isAfterUntil) {
                return RecurrenceExpansion(starts: state.emitted, truncated: state.truncated)
            }
            periodIndex += 1
        }
        return RecurrenceExpansion(starts: state.emitted, truncated: state.truncated || iterations >= maxIterations)
    }

    private struct State {
        let start: LocalDateTime
        let rule: RecurrenceRule
        let windowStart: LocalDateTime
        let horizon: LocalDateTime
        let maxOccurrences: Int
        var produced = 0
        var emitted: [LocalDateTime] = []
        var truncated = false

        init(
            start: LocalDateTime, rule: RecurrenceRule, windowStart: LocalDateTime, horizon: LocalDateTime,
            maxOccurrences: Int
        ) {
            self.start = start
            self.rule = rule
            self.windowStart = windowStart
            self.horizon = horizon
            self.maxOccurrences = maxOccurrences
        }

        /// Records a candidate; returns false when expansion must stop.
        mutating func consider(_ candidate: LocalDateTime, _ isAfterUntil: (LocalDateTime) -> Bool) -> Bool {
            if candidate < start { return true }
            if isAfterUntil(candidate) || candidate > horizon { return false }
            produced += 1
            if let count = rule.count, produced > count { return false }
            if candidate >= windowStart {
                guard emitted.count < maxOccurrences else {
                    truncated = true
                    return false
                }
                emitted.append(candidate)
            }
            return true
        }
    }

    /// The first date of the `index`-th period.
    private static func periodStart(for rule: RecurrenceRule, start: LocalDateTime, index: Int) -> LocalDate? {
        let step = index * rule.interval
        switch rule.frequency {
        case .daily:
            return start.date.adding(days: step)
        case .weekly:
            let offset = (start.date.weekday.rawValue - rule.weekStart.rawValue + 7) % 7
            return start.date.adding(days: -offset + step * 7)
        case .monthly:
            return LocalDate(year: start.date.year, month: start.date.month, day: 1)?.adding(months: step)
        case .yearly:
            return LocalDate(year: start.date.year + step, month: 1, day: 1)
        case .secondly, .minutely, .hourly:
            return nil
        }
    }

    private static func candidates(for rule: RecurrenceRule, start: LocalDateTime, period: LocalDate) -> [LocalDate] {
        switch rule.frequency {
        case .daily:
            return passesFilters(period, rule: rule, includeWeekdays: true) ? [period] : []
        case .weekly:
            let weekdays = rule.byDay.isEmpty ? [start.date.weekday] : rule.byDay.map(\.weekday)
            let dates = Set(weekdays).map { weekday in
                period.adding(days: (weekday.rawValue - rule.weekStart.rawValue + 7) % 7)
            }
            return dates.filter { passesFilters($0, rule: rule, includeWeekdays: false) }.sorted()
        case .monthly:
            guard rule.byMonth.isEmpty || rule.byMonth.contains(period.month) else { return [] }
            return monthDays(year: period.year, month: period.month, rule: rule, startDay: start.date.day)
        case .yearly:
            return yearDates(year: period.year, rule: rule, start: start.date)
        case .secondly, .minutely, .hourly:
            return []
        }
    }

    private static func passesFilters(_ date: LocalDate, rule: RecurrenceRule, includeWeekdays: Bool) -> Bool {
        if !rule.byMonth.isEmpty, !rule.byMonth.contains(date.month) { return false }
        if !rule.byMonthDay.isEmpty {
            let length = LocalDate.daysInMonth(year: date.year, month: date.month)
            let matches = rule.byMonthDay.contains { $0 > 0 ? $0 == date.day : length + $0 + 1 == date.day }
            if !matches { return false }
        }
        if includeWeekdays, !rule.byDay.isEmpty, !rule.byDay.contains(where: { $0.weekday == date.weekday }) {
            return false
        }
        return true
    }

    private static func monthDays(year: Int, month: Int, rule: RecurrenceRule, startDay: Int) -> [LocalDate] {
        let length = LocalDate.daysInMonth(year: year, month: month)
        var days: Set<Int>?
        if !rule.byMonthDay.isEmpty {
            days = Set(rule.byMonthDay.map { $0 > 0 ? $0 : length + $0 + 1 }.filter { (1...length).contains($0) })
        }
        if !rule.byDay.isEmpty {
            var weekdayDays = Set<Int>()
            for entry in rule.byDay {
                let matching = (1...length).filter {
                    LocalDate(year: year, month: month, day: $0)?.weekday == entry.weekday
                }
                if let ordinal = entry.ordinal {
                    if let day = select(matching, ordinal: ordinal) { weekdayDays.insert(day) }
                } else {
                    weekdayDays.formUnion(matching)
                }
            }
            days = days.map { $0.intersection(weekdayDays) } ?? weekdayDays
        }
        let resolved = days ?? (startDay <= length ? [startDay] : [])
        return resolved.sorted().compactMap { LocalDate(year: year, month: month, day: $0) }
    }

    private static func yearDates(year: Int, rule: RecurrenceRule, start: LocalDate) -> [LocalDate] {
        if !rule.byMonth.isEmpty {
            if rule.byMonthDay.isEmpty && rule.byDay.isEmpty {
                return rule.byMonth.sorted().compactMap { LocalDate(year: year, month: $0, day: start.day) }
            }
            return rule.byMonth.sorted().flatMap { monthDays(year: year, month: $0, rule: rule, startDay: start.day) }
        }
        if !rule.byMonthDay.isEmpty {
            return (1...12).flatMap { monthDays(year: year, month: $0, rule: rule, startDay: start.day) }
        }
        if !rule.byDay.isEmpty {
            guard let first = LocalDate(year: year, month: 1, day: 1) else { return [] }
            let length = LocalDate.isLeapYear(year) ? 366 : 365
            let allDays = (0..<length).map { first.adding(days: $0) }
            var result = Set<LocalDate>()
            for entry in rule.byDay {
                let matching = allDays.filter { $0.weekday == entry.weekday }
                if let ordinal = entry.ordinal {
                    if let index = select(Array(matching.indices), ordinal: ordinal) { result.insert(matching[index]) }
                } else {
                    result.formUnion(matching)
                }
            }
            return result.sorted()
        }
        return LocalDate(year: year, month: start.month, day: start.day).map { [$0] } ?? []
    }

    private static func select<T>(_ list: [T], ordinal: Int) -> T? {
        if ordinal > 0 { return ordinal <= list.count ? list[ordinal - 1] : nil }
        return -ordinal <= list.count ? list[list.count + ordinal] : nil
    }

    private static func applySetPositions(_ rule: RecurrenceRule, _ dates: [LocalDate]) -> [LocalDate] {
        guard !rule.bySetPosition.isEmpty else { return dates }
        let sorted = dates.sorted()
        return Set(rule.bySetPosition.compactMap { select(sorted, ordinal: $0) }).sorted()
    }
}
