// Readable and spoken renderings of local dates and times for the brief.

import Foundation
import LisaTime

/// Formatting used by both brief versions.
enum BriefFormatting {
    static let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December",
    ]

    /// "9:00 AM" for the readable brief.
    static func time(_ instant: Date, _ zone: TimeZone) -> String {
        let local = ZoneRules.local(for: instant, in: zone).time
        let hour = local.hour % 12 == 0 ? 12 : local.hour % 12
        return String(format: "%d:%02d %@", hour, local.minute, local.hour < 12 ? "AM" : "PM")
    }

    /// "9 AM" or "9:30 AM" for speech.
    static func spokenTime(_ instant: Date, _ zone: TimeZone) -> String {
        let local = ZoneRules.local(for: instant, in: zone).time
        if local.hour == 12 && local.minute == 0 { return "noon" }
        let hour = local.hour % 12 == 0 ? 12 : local.hour % 12
        let suffix = local.hour < 12 ? "AM" : "PM"
        return local.minute == 0 ? "\(hour) \(suffix)" : String(format: "%d:%02d %@", hour, local.minute, suffix)
    }

    /// "Monday, November 16".
    static func day(_ date: LocalDate) -> String {
        "\(date.weekday.displayName), \(monthNames[date.month - 1]) \(date.day)"
    }

    /// "today", "tomorrow", or "Thursday, November 19" relative to `reference`.
    static func relativeDay(_ date: LocalDate, reference: LocalDate) -> String {
        switch reference.days(until: date) {
        case 0: "today"
        case 1: "tomorrow"
        case -1: "yesterday"
        default: day(date)
        }
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}
