// The `brief` section: morning-brief time, length, speaking rate, catch-up window and topics.

import LisaDomain

/// Decodes `brief` into the brief settings (BRIEF-03, BRIEF-04, REM-04). Absent settings keep the R1 defaults of
/// `BriefSettings()`: 06:30, a 220-word target, 150 words per minute, a 4-hour catch-up window and no topics.
enum BriefSection {
    static func decode(_ section: ConfigSection?) -> BriefSettings {
        let defaults = BriefSettings()
        guard let section else { return defaults }
        defer { section.finish() }
        return BriefSettings(
            deliveryTime: section.time("deliveryTime", default: defaults.deliveryTime),
            targetWords: section.integer("targetWords", default: defaults.targetWords, in: 50...3000),
            wordsPerMinute: section.integer("wordsPerMinute", default: defaults.wordsPerMinute, in: 60...400),
            catchUpWindowHours: section.integer("catchUpWindowHours", default: defaults.catchUpWindowHours, in: 0...24),
            topics: section.textList("topics", default: defaults.topics, maxCount: 100))
    }
}
