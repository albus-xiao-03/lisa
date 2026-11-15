// Parses Internet message dates (RFC 5322, including obsolete zone names) and ISO 8601 timestamps.

import Foundation

/// Parses dates found in mail headers and feeds. Unparseable text yields `nil`, never a guessed date.
public enum InternetDateParser {
    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10,
        "nov": 11, "dec": 12,
    ]

    private static let zoneOffsets: [String: Int] = [
        "UT": 0, "GMT": 0, "Z": 0, "UTC": 0, "EST": -5, "EDT": -4, "CST": -6, "CDT": -5, "MST": -7, "MDT": -6,
        "PST": -8, "PDT": -7,
    ]

    /// Parses an RFC 5322 date such as `Mon, 16 Nov 2026 09:30:00 -0500`.
    public static func parseRFC5322(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comment = value.firstIndex(of: "(") { value = String(value[..<comment]) }
        if let comma = value.firstIndex(of: ",") { value = String(value[value.index(after: comma)...]) }
        let tokens = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 4, let day = Int(tokens[0]),
            let month = monthNumbers[String(tokens[1].lowercased().prefix(3))], var year = Int(tokens[2])
        else { return nil }
        if year < 50 { year += 2000 } else if year < 1000 { year += 1900 }
        let timeParts = tokens[3].split(separator: ":").compactMap { Int($0) }
        guard timeParts.count >= 2, timeParts.count <= 3, let date = LocalDate(year: year, month: month, day: day),
            let time = LocalTime(
                hour: timeParts[0], minute: timeParts[1], second: timeParts.count == 3 ? timeParts[2] : 0)
        else { return nil }
        let offset = tokens.count >= 5 ? zoneOffsetSeconds(tokens[4]) : 0
        guard let offset else { return nil }
        let local = LocalDateTime(date: date, time: time)
        return Date(timeIntervalSince1970: TimeInterval(local.secondsSinceEpoch - offset))
    }

    /// Parses an ISO 8601 / RFC 3339 timestamp, with or without fractional seconds.
    public static func parseISO8601(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? Date(value, strategy: .iso8601) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(value) { return date }
        if let date = LocalDate(iso: value) {
            return Date(timeIntervalSince1970: TimeInterval(date.daysSinceEpoch * 86_400))
        }
        return nil
    }

    /// Parses either form.
    public static func parse(_ text: String) -> Date? {
        parseISO8601(text) ?? parseRFC5322(text)
    }

    private static func zoneOffsetSeconds(_ token: String) -> Int? {
        if let hours = zoneOffsets[token.uppercased()] { return hours * 3600 }
        guard token.count == 5, let sign = token.first, sign == "+" || sign == "-",
            let digits = Int(token.dropFirst())
        else { return token.count == 1 ? 0 : nil }
        let seconds = (digits / 100) * 3600 + (digits % 100) * 60
        return sign == "-" ? -seconds : seconds
    }
}
