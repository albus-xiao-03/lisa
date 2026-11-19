// Parsing of the HTTP Retry-After field (RFC 9110 §10.2.3): delay-seconds or an HTTP-date in any of its three
// formats (§5.6.7).

import Foundation

/// Reads `Retry-After` values.
public enum RetryAfter {
    /// The longest wait honoured; larger values are clamped so a hostile server cannot park a source forever.
    public static let maxDelaySeconds = 86_400 * 7

    /// The instant after which a retry is allowed, or nil when the value is absent or malformed.
    public static func date(from value: String, now: Date) -> Date? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) {
            let seconds = text.utf8.count > 9 ? maxDelaySeconds : min(Int(text) ?? maxDelaySeconds, maxDelaySeconds)
            return now.addingTimeInterval(TimeInterval(seconds))
        }
        guard let date = HTTPDate.parse(text, now: now) else { return nil }
        let latest = now.addingTimeInterval(TimeInterval(maxDelaySeconds))
        return min(max(date, now), latest)
    }

    /// The `Retry-After` instant in `response`, if it has a valid one.
    public static func date(in response: HTTPResponse, now: Date) -> Date? {
        response.header("Retry-After").flatMap { date(from: $0, now: now) }
    }
}

/// HTTP-date parsing: IMF-fixdate, the obsolete RFC 850 format and asctime (RFC 9110 §5.6.7), all in UTC.
public enum HTTPDate {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let shortDays: Set<String> = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let longDays: Set<String> = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    public static func parse(_ text: String, now: Date = Date()) -> Date? {
        let fields = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
        if fields.count == 6, fields[0].hasSuffix(","), shortDays.contains(String(fields[0].dropLast())),
            fields[5] == "GMT", let day = Int(fields[1]), fields[1].count == 2,
            let month = months.firstIndex(of: fields[2]), let year = Int(fields[3]), fields[3].count == 4
        {
            return compose(year: year, month: month + 1, day: day, time: fields[4])
        }
        // RFC 850: Sunday, 06-Nov-94 08:49:37 GMT
        if fields.count == 4, fields[0].hasSuffix(","), longDays.contains(String(fields[0].dropLast())),
            fields[3] == "GMT"
        {
            let parts = fields[1].split(separator: "-").map(String.init)
            guard parts.count == 3, parts[0].count == 2, let day = Int(parts[0]),
                let month = months.firstIndex(of: parts[1]), parts[2].count == 2, let shortYear = Int(parts[2])
            else { return nil }
            // Two-digit years more than 50 years in the future mean the most recent past year with those digits.
            let currentYear = Calendar(identifier: .gregorian).dateComponents(in: utc, from: now).year ?? 2000
            var year = (currentYear / 100) * 100 + shortYear
            if year > currentYear + 50 { year -= 100 }
            return compose(year: year, month: month + 1, day: day, time: fields[2])
        }
        // asctime: Sun Nov  6 08:49:37 1994
        if fields.count == 5, shortDays.contains(fields[0]), let month = months.firstIndex(of: fields[1]),
            (1...2).contains(fields[2].count), let day = Int(fields[2]), let year = Int(fields[4]), fields[4].count == 4
        {
            return compose(year: year, month: month + 1, day: day, time: fields[3])
        }
        return nil
    }

    private static let utc = TimeZone(identifier: "UTC")!

    private static func compose(year: Int, month: Int, day: Int, time: String) -> Date? {
        let parts = time.split(separator: ":").map(String.init)
        guard parts.count == 3, parts.allSatisfy({ $0.count == 2 }), let hour = Int(parts[0]),
            let minute = Int(parts[1]), let second = Int(parts[2]), (0...23).contains(hour), (0...59).contains(minute),
            (0...60).contains(second), (1...31).contains(day)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = DateComponents(
            timeZone: utc, year: year, month: month, day: day, hour: hour, minute: minute, second: min(second, 59))
        // Out-of-range days such as 31 Feb are rejected rather than rolled over.
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
