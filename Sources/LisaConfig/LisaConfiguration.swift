// The validated Lisa configuration (CFG-01): every section, typed, with the accessors the host composes from.

import Foundation
import LisaDomain
import LisaTime

/// A validated configuration, schema version 1 (CFG-01). Only `ConfigurationLoader` creates one, so every value has
/// passed validation, and every section the file leaves out holds its safe default (CFG-02): delivery dry-run,
/// email and calls disabled, no APNs, the deterministic model with local-only sharing, and the API on loopback.
public struct LisaConfiguration: Hashable, Sendable {
    /// The schema version of the file, `ConfigurationLoader.supportedVersion`.
    public let version: Int
    /// Where the configuration was read from, such as its file path, for reports.
    public let sourceName: String
    /// The absolute data directory, with a leading `~` expanded.
    public let dataDirectory: String
    /// The IANA zone for planning, briefing and reminders.
    public let timeZone: TimeZoneID
    /// Planning windows, protected time and scheduling defaults.
    public let planning: PlanningSettings
    /// Explicit readings for ambiguous written dates.
    public let dateReading: DateReadingSettings
    /// Morning-brief timing, length and catch-up window.
    public let brief: BriefSettings
    /// Reminder rules and quiet hours.
    public let reminders: ReminderSettings
    /// News interests and mutes.
    public let news: NewsConfiguration
    /// Delivery modes, enablement, the owner's approved contacts and delivery limits.
    public let delivery: DeliveryConfiguration
    /// The SMTP adapter, when configured.
    public let email: EmailAdapterConfiguration?
    /// The Twilio call adapter, when configured.
    public let calls: CallAdapterConfiguration?
    /// Notification policy and the optional APNs provider.
    public let notifications: NotificationConfiguration
    /// The model provider, endpoint, data-sharing policy and limits.
    public let model: ModelConfiguration
    /// The configured sources, in file order.
    public let sources: [SourceConfiguration]
    /// The host API's bind address, port and TLS.
    public let api: APIConfiguration
    /// Retention periods.
    public let retention: RetentionConfiguration
    /// Resource bounds.
    public let limits: ResourceLimits

    /// The data directory as a file URL.
    public var dataDirectoryURL: URL {
        URL(fileURLWithPath: dataDirectory, isDirectory: true)
    }

    /// The sources scheduled for synchronization.
    public var enabledSources: [SourceConfiguration] {
        sources.filter(\.enabled)
    }

    /// The source with `key`, if configured.
    public func source(forKey key: String) -> SourceConfiguration? {
        sources.first { $0.key == key }
    }

    /// Whether any channel is set to deliver for real.
    public var hasLiveDelivery: Bool {
        [delivery.modes.email, delivery.modes.call, delivery.modes.push].contains(.live)
    }
}
