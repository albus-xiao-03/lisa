// Resource bounds for parsing and expanding calendars (OPS-02).

/// Limits applied to every calendar parse and expansion. Exceeding one is reported, never silently ignored.
public struct ICalendarLimits: Hashable, Sendable {
    public var maxInputBytes: Int
    public var maxLineLength: Int
    public var maxLines: Int
    public var maxNestingDepth: Int
    public var maxEvents: Int
    public var maxOccurrencesPerEvent: Int
    public var maxTotalOccurrences: Int
    /// Upper bound on recurrence periods examined per rule, so rules that rarely match still terminate.
    public var maxRecurrenceIterations: Int

    public init(
        maxInputBytes: Int = 8_000_000, maxLineLength: Int = 16_384, maxLines: Int = 400_000, maxNestingDepth: Int = 8,
        maxEvents: Int = 10_000, maxOccurrencesPerEvent: Int = 1_000, maxTotalOccurrences: Int = 20_000,
        maxRecurrenceIterations: Int = 50_000
    ) {
        self.maxInputBytes = maxInputBytes
        self.maxLineLength = maxLineLength
        self.maxLines = maxLines
        self.maxNestingDepth = maxNestingDepth
        self.maxEvents = maxEvents
        self.maxOccurrencesPerEvent = maxOccurrencesPerEvent
        self.maxTotalOccurrences = maxTotalOccurrences
        self.maxRecurrenceIterations = maxRecurrenceIterations
    }
}
