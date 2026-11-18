// Test-only. Builds synthetic iCalendar text and expands it with the production parser and expander, for the calendar,
// limits and time-case suites (L06, L22, §16.3) and later calendar-ingestion tests (L07).

import Foundation
import LisaICalendar
import LisaTime

/// Synthetic VCALENDAR text made of VEVENT and VTIMEZONE blocks, rendered with CRLF line endings.
enum SyntheticCalendar {
    /// An Outlook-style `VTIMEZONE` named "Eastern Standard Time", with the current US Eastern rules.
    static let easternStandardTime = """
        BEGIN:VTIMEZONE
        TZID:Eastern Standard Time
        BEGIN:STANDARD
        DTSTART:16011104T020000
        RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
        TZOFFSETFROM:-0400
        TZOFFSETTO:-0500
        END:STANDARD
        BEGIN:DAYLIGHT
        DTSTART:16010311T020000
        RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
        TZOFFSETFROM:-0500
        TZOFFSETTO:-0400
        END:DAYLIGHT
        END:VTIMEZONE
        """

    /// A VEVENT with `UID`, `SUMMARY` and the given property lines, such as `DTSTART;TZID=America/New_York:…`.
    static func event(uid: String, summary: String, _ properties: String...) -> String {
        (["BEGIN:VEVENT", "UID:\(uid)", "SUMMARY:\(summary)"] + properties + ["END:VEVENT"]).joined(separator: "\n")
    }

    /// A VCALENDAR holding `components` (VEVENT or VTIMEZONE blocks).
    static func calendar(name: String? = nil, _ components: String...) -> String {
        calendar(name: name, components: components)
    }

    /// A VCALENDAR holding `components` (VEVENT or VTIMEZONE blocks).
    static func calendar(name: String? = nil, components: [String]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Lisa Tests//Synthetic//EN"]
        if let name { lines.append("X-WR-CALNAME:\(name)") }
        return (lines + components + ["END:VCALENDAR"]).joined(separator: "\n").replacingOccurrences(
            of: "\n", with: "\r\n") + "\r\n"
    }

    /// The UTC window from `start` to `end`, written `YYYY-MM-DDTHH:MM`.
    static func window(_ start: String, _ end: String) -> TimeRange {
        TimeRange(uncheckedStart: TestTime.utcInstant(start), end: TestTime.utcInstant(end))
    }

    /// Parses `text` and expands it over `window`, interpreting floating times in `floatingZone`.
    static func expand(
        _ text: String, window: TimeRange, floatingZone: TimeZoneID = TestTime.newYork,
        limits: ICalendarLimits = ICalendarLimits()
    ) throws -> ExpandedCalendar {
        let parsed = try ICalParser.parseCalendar(text, limits: limits)
        let options = CalendarExpansionOptions(window: window, floatingZone: floatingZone.timeZone, limits: limits)
        return CalendarExpander.expand(parsed, options: options)
    }
}
