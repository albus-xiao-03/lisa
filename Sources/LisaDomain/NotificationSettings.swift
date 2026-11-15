// Host-wide notification policy: default routing, content level and the Time Sensitive opt-in rule.

/// Notification policy settings.
public struct NotificationSettings: Hashable, Codable, Sendable {
    /// Whether host notifications are generated at all.
    public var enabled: Bool
    /// Owner opt-in: urgent confirmed deadlines may use the Time Sensitive level.
    public var timeSensitiveForUrgentDeadlines: Bool
    /// A confirmed high-priority deadline within this many minutes, with the task incomplete, is urgent.
    public var urgentDeadlineWindowMinutes: Int
    /// How long a reminder notification stays deliverable after it is due, when the subject has no later bound.
    public var defaultValidityMinutes: Int
    /// Whether brief availability is notified (once per daily brief).
    public var notifyBriefAvailability: Bool

    public init(
        enabled: Bool = true, timeSensitiveForUrgentDeadlines: Bool = false, urgentDeadlineWindowMinutes: Int = 15,
        defaultValidityMinutes: Int = 240, notifyBriefAvailability: Bool = true
    ) {
        self.enabled = enabled
        self.timeSensitiveForUrgentDeadlines = timeSensitiveForUrgentDeadlines
        self.urgentDeadlineWindowMinutes = urgentDeadlineWindowMinutes
        self.defaultValidityMinutes = defaultValidityMinutes
        self.notifyBriefAvailability = notifyBriefAvailability
    }
}
