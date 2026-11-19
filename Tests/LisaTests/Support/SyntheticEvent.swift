// Test-only. A synthetic calendar event written in New York local time, and the iCalendar file text for a list of
// them, for the suites that ingest calendars through a configured source (L07, L08, L12, L13, L19, §16.3).

import Foundation

/// One synthetic event. Times are local `YYYY-MM-DDTHH:MM` in America/New_York, the §16.2 zone.
struct SyntheticEvent: Sendable {
    var uid: String
    var title: String
    var start: String
    var end: String
    /// More property lines, such as `TRANSP:TRANSPARENT` or `DESCRIPTION:…`.
    var properties: [String] = []

    /// The VEVENT block.
    var component: String {
        let times = [
            "DTSTART;TZID=America/New_York:\(Self.stamp(start))", "DTEND;TZID=America/New_York:\(Self.stamp(end))",
        ]
        return (["BEGIN:VEVENT", "UID:\(uid)", "SUMMARY:\(title)"] + times + properties + ["END:VEVENT"])
            .joined(separator: "\n")
    }

    /// A VCALENDAR holding `events`, with CRLF line endings.
    static func calendar(_ events: [SyntheticEvent]) -> String {
        SyntheticCalendar.calendar(name: "Synthetic calendar", components: events.map(\.component))
    }

    /// `2026-11-16T09:00` as the iCalendar local form `20261116T090000`.
    static func stamp(_ local: String) -> String {
        local.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "") + "00"
    }
}
