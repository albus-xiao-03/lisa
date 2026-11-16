// The `dateReading` section: explicit owner choices that settle otherwise ambiguous written dates.

import LisaTime

/// Decodes `dateReading` (DATA-03, D-04). By default nothing is settled: numeric dates such as 03/04 and
/// "next Friday" stay ambiguous until the owner chooses a reading here.
enum DateReadingSection {
    static func decode(_ section: ConfigSection?) -> DateReadingSettings {
        let defaults = DateReadingSettings()
        guard let section else { return defaults }
        defer { section.finish() }
        return DateReadingSettings(
            numericDateOrder: section.optionalChoice(
                "numericDateOrder", options: [NumericDateOrder.monthFirst, .dayFirst]),
            nextWeekday: section.choice(
                "nextWeekday", default: defaults.nextWeekday,
                options: [NextWeekdayReading.ambiguous, .followingWeek, .nearestUpcoming]))
    }
}
