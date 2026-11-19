// A local calendar date from the host (`YYYY-MM-DD`) in the device's words, such as "Tuesday, November 17, 2026".

import Foundation

/// Words for the API's `YYYY-MM-DD` dates. The date names a calendar day, so it is formatted as that day wherever the
/// device is.
enum LocalDayText {
    /// `date` in the device's words with `style`, or the text unchanged when it is not a `YYYY-MM-DD` calendar date.
    /// The parser is lenient (it reads `2026-02-30` as March 2), so a date that does not read back the same is shown
    /// as it is.
    static func words(for date: String, style: Date.FormatStyle.DateStyle) -> String {
        let parser = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        guard let day = try? parser.parse(date), parser.format(day) == date else { return date }
        return day.formatted(Date.FormatStyle(date: style, time: .omitted, timeZone: .gmt))
    }
}
