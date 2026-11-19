// The `limits` section: bounds on message and feed sizes, sync passes, recurrence expansion, requests and logs.

/// Resource bounds (OPS-02, INGEST-01). Every bound is finite; the defaults match the engines' own defaults.
public struct ResourceLimits: Hashable, Sendable {
    /// The largest email message accepted, in bytes.
    public let maxMessageBytes: Int
    /// The largest feed document accepted, in bytes.
    public let maxFeedBytes: Int
    /// The most items one synchronization pass takes from a source; the rest wait for the next pass.
    public let maxItemsPerSync: Int
    /// The most bytes one synchronization pass takes from a source.
    public let maxBytesPerSync: Int
    /// The time allowed for one synchronization pass of one source.
    public let syncTimeoutSeconds: Int
    /// The most occurrences expanded from one recurring event.
    public let maxRecurrenceOccurrencesPerEvent: Int
    /// The most occurrences expanded from one calendar.
    public let maxTotalOccurrences: Int
    /// The most network requests in flight at once.
    public let maxConcurrentRequests: Int
    /// The size at which the log file is rotated, in bytes.
    public let logMaxBytes: Int
    /// How many rotated log files are kept.
    public let logKeepFiles: Int
    /// The most raw source content kept in total, in bytes; the oldest content is removed first beyond it.
    public let rawContentMaxBytes: Int

    /// 25 MB messages, 10 MB feeds, 200 items and 50 MB per pass, 60-second passes, 1,000 occurrences per event and
    /// 20,000 per calendar, 4 concurrent requests, 5 MB log files with 3 kept, and 500 MB of raw content.
    public static let defaultValue = ResourceLimits(
        maxMessageBytes: 25_000_000, maxFeedBytes: 10_000_000, maxItemsPerSync: 200, maxBytesPerSync: 50_000_000,
        syncTimeoutSeconds: 60, maxRecurrenceOccurrencesPerEvent: 1000, maxTotalOccurrences: 20_000,
        maxConcurrentRequests: 4, logMaxBytes: 5_000_000, logKeepFiles: 3, rawContentMaxBytes: 500_000_000)

    static func decode(_ section: ConfigSection?) -> ResourceLimits {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return ResourceLimits(
            maxMessageBytes: section.integer(
                "maxMessageBytes", default: defaults.maxMessageBytes, in: 1024...100_000_000),
            maxFeedBytes: section.integer("maxFeedBytes", default: defaults.maxFeedBytes, in: 1024...50_000_000),
            maxItemsPerSync: section.integer("maxItemsPerSync", default: defaults.maxItemsPerSync, in: 1...5000),
            maxBytesPerSync: section.integer(
                "maxBytesPerSync", default: defaults.maxBytesPerSync, in: 1024...1_000_000_000),
            syncTimeoutSeconds: section.integer(
                "syncTimeoutSeconds", default: defaults.syncTimeoutSeconds, in: 5...3600),
            maxRecurrenceOccurrencesPerEvent: section.integer(
                "maxRecurrenceOccurrencesPerEvent", default: defaults.maxRecurrenceOccurrencesPerEvent, in: 1...10_000),
            maxTotalOccurrences: section.integer(
                "maxTotalOccurrences", default: defaults.maxTotalOccurrences, in: 1...200_000),
            maxConcurrentRequests: section.integer(
                "maxConcurrentRequests", default: defaults.maxConcurrentRequests, in: 1...32),
            logMaxBytes: section.integer("logMaxBytes", default: defaults.logMaxBytes, in: 65_536...1_000_000_000),
            logKeepFiles: section.integer("logKeepFiles", default: defaults.logKeepFiles, in: 1...100),
            rawContentMaxBytes: section.integer(
                "rawContentMaxBytes", default: defaults.rawContentMaxBytes, in: 1_000_000...1_000_000_000_000))
    }
}
