// Checks that a downloaded body is a whole iCalendar document before it is offered as a complete snapshot: not
// empty, not a web page, UTF-8 text, beginning with BEGIN:VCALENDAR and reaching END:VCALENDAR.

import Foundation
import LisaHTTPSources
import LisaPorts

/// Content sniffing for calendar subscriptions. A body that fails these checks is never offered as a snapshot, so it
/// can never make reconciliation cancel events (CAL-02).
enum CalendarContentCheck {
    private static let begin = Array("BEGIN:VCALENDAR".utf8)
    private static let end = Array("END:VCALENDAR".utf8)

    /// Nil when `body` can be offered as a complete calendar; otherwise the classified reason.
    static func error(in body: Data, mediaType: MediaType?) -> ConnectorError? {
        let bytes = [UInt8](body)
        guard !bytes.allSatisfy(isSpace) else {
            return ConnectorError(.parse, "the server returned an empty document instead of calendar data")
        }
        let wideBOMs: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF], [0, 0, 0xFE, 0xFF]]
        if wideBOMs.contains(where: { bytes.starts(with: $0) }) {
            return ConnectorError(
                .unsupported,
                "the calendar is UTF-16 or UTF-32 text; iCalendar subscriptions are read as UTF-8 (RFC 5545)")
        }
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while start < bytes.count, isSpace(bytes[start]) { start += 1 }
        guard matches(begin, in: bytes, at: start) else {
            return ConnectorError(.parse, notCalendarSummary(bytes, from: start))
        }
        guard String(validating: bytes, as: UTF8.self) != nil else {
            let declared = mediaType?.charset.map { " (the server declared the \($0) character set)" } ?? ""
            return ConnectorError(.parse, "the calendar is not valid UTF-8 text\(declared)")
        }
        guard hasLine(starting: end, in: bytes, after: start) else {
            return ConnectorError(
                .partial, "the calendar ends before END:VCALENDAR; the download may have been cut short")
        }
        return nil
    }

    /// Why a body that does not begin with BEGIN:VCALENDAR was refused.
    private static func notCalendarSummary(_ bytes: [UInt8], from start: Int) -> String {
        guard start < bytes.count else { return "the server returned an empty document instead of calendar data" }
        switch bytes[start] {
        case UInt8(ascii: "<"):
            let head = String(decoding: bytes[start..<min(bytes.count, start + 1_024)], as: UTF8.self).lowercased()
            if head.contains("<html") || head.contains("<!doctype html") {
                return "the server returned a web page instead of calendar data; a private address may have been"
                    + " reset or may need signing in"
            }
            return "the server returned an XML or HTML document instead of calendar data"
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return "the server returned JSON instead of calendar data"
        default:
            return "the server returned data that is not an iCalendar document"
        }
    }

    /// Whether `marker` (upper-case ASCII) occurs at `index`, ignoring ASCII case.
    private static func matches(_ marker: [UInt8], in bytes: [UInt8], at index: Int) -> Bool {
        guard index >= 0, index + marker.count <= bytes.count else { return false }
        for offset in marker.indices where upper(bytes[index + offset]) != marker[offset] { return false }
        return true
    }

    /// Whether a line after `start` begins with `marker`, searching from the end, where it normally is.
    private static func hasLine(starting marker: [UInt8], in bytes: [UInt8], after start: Int) -> Bool {
        var index = bytes.count - marker.count
        while index > start {
            let previous = bytes[index - 1]
            if previous == 0x0A || previous == 0x0D, matches(marker, in: bytes, at: index) { return true }
            index -= 1
        }
        return false
    }

    private static func upper(_ byte: UInt8) -> UInt8 {
        (0x61...0x7A).contains(byte) ? byte - 0x20 : byte
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
