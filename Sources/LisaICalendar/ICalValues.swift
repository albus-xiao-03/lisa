// iCalendar value types: DATE, DATE-TIME (UTC, zoned, floating), DURATION, UTC-OFFSET and TEXT escaping.

import Foundation
import LisaTime

/// A DATE or DATE-TIME value with its time semantics preserved.
public enum TimeValue: Hashable, Sendable {
    case utc(Date)
    case zoned(LocalDateTime, tzid: String)
    case floating(LocalDateTime)
    case date(LocalDate)

    /// Whether the value is date-only.
    public var isDate: Bool {
        if case .date = self { true } else { false }
    }

    /// The local date-time as written (UTC values are expressed in UTC).
    public var writtenLocal: LocalDateTime {
        switch self {
        case .utc(let instant): ZoneRules.local(for: instant, rules: FixedOffsetRules(seconds: 0))
        case .zoned(let local, _), .floating(let local): local
        case .date(let date): LocalDateTime(date: date, time: .midnight)
        }
    }
}

/// Parsers for iCalendar value formats.
public enum ICalValues {
    /// Parses `YYYYMMDD`.
    public static func date(_ text: String) -> LocalDate? {
        guard text.count == 8, text.allSatisfy(\.isNumber),
            let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)),
            let day = Int(text.suffix(2))
        else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }

    /// Parses `YYYYMMDDTHHMMSS` with an optional trailing `Z`.
    public static func dateTime(_ text: String) -> (LocalDateTime, isUTC: Bool)? {
        let isUTC = text.hasSuffix("Z") || text.hasSuffix("z")
        let body = isUTC ? String(text.dropLast()) : text
        let parts = body.split(separator: "T")
        guard parts.count == 2, parts[1].count == 6, parts[1].allSatisfy(\.isNumber),
            let date = date(String(parts[0])), let hour = Int(parts[1].prefix(2)),
            let minute = Int(parts[1].dropFirst(2).prefix(2)), let second = Int(parts[1].suffix(2)),
            let time = LocalTime(hour: hour, minute: minute, second: min(second, 59))
        else { return nil }
        return (LocalDateTime(date: date, time: time), isUTC)
    }

    /// Parses a DTSTART-like property, honoring `VALUE=DATE` and `TZID`.
    public static func timeValue(_ line: ContentLine) -> TimeValue? {
        timeValue(line.value, valueType: line.parameter("VALUE"), tzid: line.parameter("TZID"))
    }

    /// Parses one DATE or DATE-TIME value.
    public static func timeValue(_ text: String, valueType: String?, tzid: String?) -> TimeValue? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if valueType?.uppercased() == "DATE" || (value.count == 8 && !value.contains("T")) {
            return date(value).map(TimeValue.date)
        }
        guard let (local, isUTC) = dateTime(value) else { return nil }
        if isUTC {
            return .utc(Date(timeIntervalSince1970: TimeInterval(local.secondsSinceEpoch)))
        }
        if let tzid, !tzid.isEmpty { return .zoned(local, tzid: tzid) }
        return .floating(local)
    }

    /// Parses a list property such as EXDATE or RDATE (comma-separated values).
    public static func timeValues(_ line: ContentLine) -> [TimeValue] {
        line.value.split(separator: ",").compactMap {
            timeValue(String($0), valueType: line.parameter("VALUE"), tzid: line.parameter("TZID"))
        }
    }

    /// Parses an RFC 5545 duration such as `PT1H30M`, `P1D` or `-P2W`, in seconds.
    public static func duration(_ text: String) -> Int? {
        var value = Substring(text.uppercased())
        var sign = 1
        if value.first == "-" {
            sign = -1
            value = value.dropFirst()
        } else if value.first == "+" {
            value = value.dropFirst()
        }
        guard value.first == "P" else { return nil }
        value = value.dropFirst()
        var total = 0
        var number = ""
        var inTime = false
        var sawComponent = false
        for character in value {
            if character.isNumber {
                number.append(character)
                continue
            }
            if character == "T" {
                inTime = true
                continue
            }
            guard let amount = Int(number) else { return nil }
            number = ""
            sawComponent = true
            switch (character, inTime) {
            case ("W", false): total += amount * 7 * 86_400
            case ("D", false): total += amount * 86_400
            case ("H", true): total += amount * 3600
            case ("M", true): total += amount * 60
            case ("S", true): total += amount
            default: return nil
            }
        }
        guard number.isEmpty, sawComponent else { return nil }
        return sign * total
    }

    /// Parses a UTC offset such as `-0500` or `+0530`, in seconds.
    public static func utcOffset(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value.count == 5 || value.count == 7, let sign = value.first, sign == "+" || sign == "-" else {
            return nil
        }
        let digits = value.dropFirst()
        guard digits.allSatisfy(\.isNumber), let hours = Int(digits.prefix(2)),
            let minutes = Int(digits.dropFirst(2).prefix(2))
        else { return nil }
        let seconds = digits.count == 6 ? Int(digits.suffix(2)) ?? 0 : 0
        let total = hours * 3600 + minutes * 60 + seconds
        return sign == "-" ? -total : total
    }

    /// Unescapes TEXT values (`\n`, `\,`, `\;`, `\\`).
    public static func unescapeText(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Escapes text for a TEXT value.
    public static func escapeText(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\\\"
            case ";": result += "\\;"
            case ",": result += "\\,"
            case "\n": result += "\\n"
            case "\r": continue
            default: result.append(character)
            }
        }
        return result
    }
}
