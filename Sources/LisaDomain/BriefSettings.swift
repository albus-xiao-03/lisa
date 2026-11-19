// Morning-brief timing, length and catch-up settings.

import LisaTime

/// Brief settings (BRIEF-03, BRIEF-04).
public struct BriefSettings: Hashable, Codable, Sendable {
    public var deliveryTime: LocalTime
    /// The concise default target length of the readable brief.
    public var targetWords: Int
    /// Used to estimate spoken duration; an estimate, not a playback guarantee.
    public var wordsPerMinute: Int
    /// After host downtime, at most one catch-up brief is produced within this window after the scheduled time.
    public var catchUpWindowHours: Int
    public var topics: [String]

    public init(
        deliveryTime: LocalTime = LocalTime(secondsSinceMidnight: 6 * 3600 + 30 * 60), targetWords: Int = 220,
        wordsPerMinute: Int = 150, catchUpWindowHours: Int = 4, topics: [String] = []
    ) {
        self.deliveryTime = deliveryTime
        self.targetWords = targetWords
        self.wordsPerMinute = wordsPerMinute
        self.catchUpWindowHours = catchUpWindowHours
        self.topics = topics
    }
}
