// The effective owner settings used by policy engines and services, assembled from configuration and preferences.

import LisaTime

/// The effective settings for planning, briefing, reminders and delivery.
public struct OwnerSettings: Hashable, Codable, Sendable {
    /// The IANA time zone used for planning and briefing.
    public var zone: TimeZoneID
    public var planning: PlanningSettings
    public var reminders: ReminderSettings
    public var calls: CallSettings
    public var delivery: DeliverySettings
    public var notifications: NotificationSettings
    public var brief: BriefSettings
    public var dateReading: DateReadingSettings
    public var newsInterests: [String]
    public var mutedSources: [String]
    public var mutedTopics: [String]

    public init(
        zone: TimeZoneID, planning: PlanningSettings = .defaultValue, reminders: ReminderSettings = ReminderSettings(),
        calls: CallSettings = CallSettings(), delivery: DeliverySettings = DeliverySettings(),
        notifications: NotificationSettings = NotificationSettings(), brief: BriefSettings = BriefSettings(),
        dateReading: DateReadingSettings = DateReadingSettings(), newsInterests: [String] = [],
        mutedSources: [String] = [], mutedTopics: [String] = []
    ) {
        self.zone = zone
        self.planning = planning
        self.reminders = reminders
        self.calls = calls
        self.delivery = delivery
        self.notifications = notifications
        self.brief = brief
        self.dateReading = dateReading
        self.newsInterests = newsInterests
        self.mutedSources = mutedSources
        self.mutedTopics = mutedTopics
    }
}
