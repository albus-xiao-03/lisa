// Resolves relative and partial date phrases against a documented reference date; ambiguity stays unresolved.

import Foundation

/// How numeric dates such as 03/04 are read. Without a setting, numeric dates whose parts are both at most 12 stay
/// ambiguous.
public enum NumericDateOrder: String, Codable, Sendable {
    case monthFirst
    case dayFirst
}

/// How "next <weekday>" is read. The default keeps it ambiguous because usage differs.
public enum NextWeekdayReading: String, Codable, Sendable {
    case ambiguous
    case followingWeek
    case nearestUpcoming
}

/// Explicit owner settings that may settle otherwise ambiguous dates.
public struct DateReadingSettings: Hashable, Codable, Sendable {
    public var numericDateOrder: NumericDateOrder?
    public var nextWeekday: NextWeekdayReading

    public init(numericDateOrder: NumericDateOrder? = nil, nextWeekday: NextWeekdayReading = .ambiguous) {
        self.numericDateOrder = numericDateOrder
        self.nextWeekday = nextWeekday
    }
}

/// The outcome of resolving a date phrase.
public enum DateResolution: Hashable, Sendable {
    case resolved(LocalDate)
    case ambiguous(candidates: [LocalDate], reason: String)
    case unrecognized
}

/// Resolves date phrases relative to a reference date: the local date of the source timestamp in its time zone.
public struct RelativeDateResolver: Sendable {
    public let referenceDate: LocalDate
    public let settings: DateReadingSettings

    public init(referenceDate: LocalDate, settings: DateReadingSettings = DateReadingSettings()) {
        self.referenceDate = referenceDate
        self.settings = settings
    }

    /// Uses the local date of `reference` in `zone` as the reference date.
    public init(reference: Date, zone: TimeZone, settings: DateReadingSettings = DateReadingSettings()) {
        self.init(referenceDate: ZoneRules.localDate(for: reference, in: zone), settings: settings)
    }

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
        "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fourteen": 14, "thirty": 30,
    ]

    /// Resolves `phrase`.
    public func resolve(_ phrase: String) -> DateResolution {
        let words = RelativeDateResolver.normalizedWords(phrase)
        guard !words.isEmpty else { return .unrecognized }
        let joined = words.joined(separator: " ")
        switch joined {
        case "today", "tonight", "this morning", "this afternoon", "this evening", "end of day", "eod":
            return .resolved(referenceDate)
        case "tomorrow", "tmrw", "tomorrow morning", "tomorrow afternoon", "tomorrow evening":
            return .resolved(referenceDate.adding(days: 1))
        case "day after tomorrow", "the day after tomorrow":
            return .resolved(referenceDate.adding(days: 2))
        case "yesterday":
            return .resolved(referenceDate.adding(days: -1))
        default:
            break
        }
        if let offset = relativeOffset(words) {
            return .resolved(referenceDate.adding(days: offset))
        }
        if let result = weekdayPhrase(words) {
            return result
        }
        if words.count == 1, let date = LocalDate(iso: words[0]) {
            return .resolved(date)
        }
        if let result = monthNamePhrase(words) {
            return result
        }
        if words.count == 1, let result = numericPhrase(words[0]) {
            return result
        }
        return .unrecognized
    }

    private static func normalizedWords(_ phrase: String) -> [String] {
        var text = phrase.lowercased()
        for mark in [",", ".", "!", "?", ";"] where !text.contains("/") || mark != "." {
            text = text.replacingOccurrences(of: mark, with: " ")
        }
        var words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        while let first = words.first, ["on", "by", "due", "before", "until", "the"].contains(first) {
            words.removeFirst()
        }
        return words.map { word in
            for suffix in ["st", "nd", "rd", "th"] where word.hasSuffix(suffix) {
                let stem = word.dropLast(2)
                if !stem.isEmpty, stem.allSatisfy(\.isNumber) { return String(stem) }
            }
            return word
        }
    }

    private func relativeOffset(_ words: [String]) -> Int? {
        guard words.count == 3, words[0] == "in" else {
            if words.count == 2, ["next", "in"].contains(words[0]), words[1] == "week" {
                return 7
            }
            return nil
        }
        guard let count = Int(words[1]) ?? RelativeDateResolver.numberWords[words[1]] else { return nil }
        switch words[2] {
        case "day", "days": return count
        case "week", "weeks": return count * 7
        default: return nil
        }
    }

    private func weekdayPhrase(_ words: [String]) -> DateResolution? {
        var qualifier: String?
        var name = words[0]
        if words.count == 2, ["this", "next", "coming"].contains(words[0]) {
            qualifier = words[0]
            name = words[1]
        } else if words.count != 1 {
            return nil
        }
        guard let weekday = Weekday.allCases.first(where: { $0.englishNames.contains(name) }) else { return nil }
        let today = referenceDate.weekday.rawValue
        let ahead = (weekday.rawValue - today + 7) % 7
        let upcoming = referenceDate.adding(days: ahead == 0 ? 7 : ahead)
        switch qualifier {
        case "this":
            return .resolved(referenceDate.adding(days: ahead))
        case "coming":
            return .resolved(upcoming)
        case "next":
            switch settings.nextWeekday {
            case .nearestUpcoming:
                return .resolved(upcoming)
            case .followingWeek:
                let mondayOfNextWeek = referenceDate.adding(days: 8 - today)
                return .resolved(mondayOfNextWeek.adding(days: weekday.rawValue - 1))
            case .ambiguous:
                return .ambiguous(
                    candidates: [upcoming, upcoming.adding(days: 7)],
                    reason: "\"next \(weekday.displayName)\" can mean the coming one or the one after it")
            }
        default:
            if ahead == 0 {
                return .ambiguous(
                    candidates: [referenceDate, referenceDate.adding(days: 7)],
                    reason: "\(weekday.displayName) is today; it may mean today or next week")
            }
            return .resolved(upcoming)
        }
    }

    private func monthNamePhrase(_ words: [String]) -> DateResolution? {
        var month: Int?
        var day: Int?
        var year: Int?
        for word in words {
            if let value = RelativeDateResolver.months[word] {
                month = value
            } else if let number = Int(word) {
                if number > 31 { year = number } else if day == nil { day = number } else { return nil }
            } else {
                return nil
            }
        }
        guard let month, let day else { return nil }
        if let year {
            return LocalDate(year: year, month: month, day: day).map(DateResolution.resolved) ?? .unrecognized
        }
        return yearlessDate(month: month, day: day)
    }

    private func numericPhrase(_ word: String) -> DateResolution? {
        let separators: Set<Character> = ["/", "."]
        guard word.contains(where: { separators.contains($0) }) else { return nil }
        let parts = word.split(whereSeparator: { separators.contains($0) }).map(String.init)
        guard parts.count == 2 || parts.count == 3, let first = Int(parts[0]), let second = Int(parts[1]) else {
            return nil
        }
        var year: Int?
        if parts.count == 3 {
            guard let value = Int(parts[2]) else { return nil }
            year = value < 100 ? 2000 + value : value
        }
        func make(month: Int, day: Int) -> DateResolution {
            if let year {
                return LocalDate(year: year, month: month, day: day).map(DateResolution.resolved) ?? .unrecognized
            }
            return yearlessDate(month: month, day: day)
        }
        if first > 12 { return make(month: second, day: first) }
        if second > 12 { return make(month: first, day: second) }
        if first == second { return make(month: first, day: second) }
        switch settings.numericDateOrder {
        case .monthFirst: return make(month: first, day: second)
        case .dayFirst: return make(month: second, day: first)
        case nil:
            let readings = [make(month: first, day: second), make(month: second, day: first)]
            let candidates = readings.flatMap { reading -> [LocalDate] in
                switch reading {
                case .resolved(let date): [date]
                case .ambiguous(let dates, _): dates
                case .unrecognized: []
                }
            }
            return .ambiguous(candidates: candidates, reason: "\(word) can be read month-first or day-first")
        }
    }

    private func yearlessDate(month: Int, day: Int) -> DateResolution {
        guard let thisYear = LocalDate(year: referenceDate.year, month: month, day: day) else {
            return .unrecognized
        }
        if thisYear >= referenceDate { return .resolved(thisYear) }
        let nextYear = LocalDate(year: referenceDate.year + 1, month: month, day: day)
        return .ambiguous(
            candidates: [thisYear] + (nextYear.map { [$0] } ?? []),
            reason: "the date has no year and has already passed this year")
    }
}
