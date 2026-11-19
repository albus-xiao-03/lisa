// Times and days in words for speech and short labels, such as "5:00 PM" and "November 20 at 5:00 PM".

import Foundation

/// Phrases a moment for Siri and for short labels, in the device's time format.
enum SpokenMoment {
    /// The time of `instant` in `zone`, such as "5:00 PM" or "17:00" depending on `locale`.
    static func time(_ instant: Date, in zone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: instant)
    }

    /// The day and time of `instant` in `zone`, such as "November 20 at 5:00 PM".
    static func dayAndTime(_ instant: Date, in zone: TimeZone, locale: Locale) -> String {
        "\(LocalDay.spokenEnglish(LocalDay.string(for: instant, in: zone))) at \(time(instant, in: zone, locale: locale))"
    }
}
