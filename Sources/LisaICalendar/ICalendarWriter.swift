// Writes .ics exports of reviewed event proposals (EVENT-01); importing them stays an owner action.

import Foundation
import LisaTime

/// An event to export.
public struct ExportEvent: Hashable, Sendable {
    public enum Start: Hashable, Sendable {
        case instant(Date, end: Date?)
        case date(LocalDate, endExclusive: LocalDate?)
    }

    public var uid: String
    public var title: String
    public var start: Start
    public var location: String?
    public var notes: String?

    public init(uid: String, title: String, start: Start, location: String? = nil, notes: String? = nil) {
        self.uid = uid
        self.title = title
        self.start = start
        self.location = location
        self.notes = notes
    }
}

/// Serializes events as an RFC 5545 VCALENDAR with escaped text and 75-octet line folding.
public enum ICalendarWriter {
    public static func write(_ events: [ExportEvent], stamp: Date) -> String {
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Lisa//R1//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
        ]
        for event in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(ICalValues.escapeText(event.uid))")
            lines.append("DTSTAMP:\(CalendarExpander.utcKey(stamp))")
            switch event.start {
            case .instant(let start, let end):
                lines.append("DTSTART:\(CalendarExpander.utcKey(start))")
                if let end { lines.append("DTEND:\(CalendarExpander.utcKey(end))") }
            case .date(let date, let endExclusive):
                lines.append("DTSTART;VALUE=DATE:\(compact(date))")
                lines.append("DTEND;VALUE=DATE:\(compact(endExclusive ?? date.adding(days: 1)))")
            }
            lines.append("SUMMARY:\(ICalValues.escapeText(event.title))")
            if let location = event.location { lines.append("LOCATION:\(ICalValues.escapeText(location))") }
            if let notes = event.notes { lines.append("DESCRIPTION:\(ICalValues.escapeText(notes))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func compact(_ date: LocalDate) -> String {
        date.iso.replacingOccurrences(of: "-", with: "")
    }

    /// Folds a line so that no physical line exceeds 75 octets, never splitting a UTF-8 sequence.
    static func fold(_ line: String) -> String {
        var result = ""
        var current = ""
        var currentOctets = 0
        var limit = 75
        for character in line {
            let octets = String(character).utf8.count
            if currentOctets + octets > limit {
                result += current + "\r\n "
                current = ""
                currentOctets = 0
                limit = 74
            }
            current.append(character)
            currentOctets += octets
        }
        return result + current
    }
}
