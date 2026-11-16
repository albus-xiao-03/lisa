// The `notifications` section: notification policy defaults and the optional APNs provider configuration.

import LisaDomain
import LisaSecrets

/// An APNs environment. Development and production are configured and used separately; a device token is only ever
/// sent to the environment it was registered for.
public enum APNsEnvironment: String, Hashable, Sendable, CaseIterable, Comparable {
    /// `api.sandbox.push.apple.com`, for development-signed apps.
    case development
    /// `api.push.apple.com`, for distribution-signed apps.
    case production

    public static func < (lhs: APNsEnvironment, rhs: APNsEnvironment) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The APNs provider (NOTIFY-04): token-based authentication with a `.p8` signing key kept in the secret store.
/// Configuring it sends nothing; real pushes also need `delivery.modes.push` set to `live`.
public struct APNsConfiguration: Hashable, Sendable {
    /// The environments device registrations may use; empty until the owner enables one.
    public let environments: Set<APNsEnvironment>
    /// The reference to the APNs authentication key (`.p8`).
    public let signingKeySecret: SecretReference
    /// The Apple Developer Team ID (10 characters), used as the token issuer.
    public let teamID: String
    /// The Key ID of the signing key (10 characters).
    public let keyID: String
    /// The app bundle identifiers that may register for pushes, such as `com.example.lisa`.
    public let topics: [String]

    static func decode(_ section: ConfigSection) -> APNsConfiguration? {
        defer { section.finish() }
        let environments = decodeEnvironments(section.section("environments"))
        let signingKeySecret = section.requiredSecret(
            "signingKeySecret",
            fix: "reference the .p8 key, such as file:/path/to/AuthKey.p8 or keychain:service/account")
        let teamID = section.requiredValidated(
            "teamID", maxLength: 10, fix: "copy the 10-character Team ID from the Apple Developer account"
        ) { appleIdentifier($0, name: "Team ID") }
        let keyID = section.requiredValidated(
            "keyID", maxLength: 10, fix: "copy the 10-character Key ID shown next to the APNs key"
        ) { appleIdentifier($0, name: "Key ID") }
        let topics = decodeTopics(section)
        guard let environments, let signingKeySecret, let teamID, let keyID, let topics else { return nil }
        return APNsConfiguration(
            environments: environments, signingKeySecret: signingKeySecret, teamID: teamID, keyID: keyID,
            topics: topics)
    }

    /// `{ development: false, production: false }`; absent environments are disabled.
    private static func decodeEnvironments(_ section: ConfigSection?) -> Set<APNsEnvironment>? {
        guard let section else { return [] }
        defer { section.finish() }
        var enabled: Set<APNsEnvironment> = []
        for environment in APNsEnvironment.allCases where section.bool(environment.rawValue, default: false) {
            enabled.insert(environment)
        }
        return enabled
    }

    private static func decodeTopics(_ section: ConfigSection) -> [String]? {
        guard let entries = section.list("topics", maxCount: 10) else { return [] }
        let topics = entries.map { $0.validated(maxLength: 155, bundleIdentifier) }
        guard topics.allSatisfy({ $0 != nil }) else { return nil }
        var seen: Set<String> = []
        return topics.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// Team IDs and Key IDs: ten uppercase ASCII letters or digits.
    private static func appleIdentifier(_ text: String, name: String) -> Result<String, ValueRefusal> {
        let valid =
            text.utf8.count == 10
            && text.unicodeScalars.allSatisfy { (0x41...0x5A).contains($0.value) || (0x30...0x39).contains($0.value) }
        return valid ? .success(text) : .failure(ValueRefusal("must be a \(name): 10 uppercase letters or digits"))
    }

    /// Reverse-DNS bundle identifiers: at least two dot-separated parts of ASCII letters, digits and hyphens.
    private static func bundleIdentifier(_ text: String) -> Result<String, ValueRefusal> {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let valid =
            parts.count >= 2
            && parts.allSatisfy { part in
                !part.isEmpty
                    && part.unicodeScalars.allSatisfy { scalar in
                        scalar.isASCII
                            && (scalar.properties.isAlphabetic || (0x30...0x39).contains(scalar.value) || scalar == "-")
                    }
            }
        return valid
            ? .success(text) : .failure(ValueRefusal("must be an app bundle identifier such as com.example.lisa"))
    }
}

/// Notification policy (NOTIFY-01, NOTIFY-03, NOTIFY-06) and the optional APNs provider.
public struct NotificationConfiguration: Hashable, Sendable {
    /// Whether the host generates notifications at all.
    public let enabled: Bool
    /// The owner's opt-in to the Time Sensitive level for urgent confirmed deadlines; off until configured.
    public let timeSensitiveForUrgentDeadlines: Bool
    /// A confirmed high-priority deadline within this many minutes, with the task incomplete, is urgent.
    public let urgentDeadlineWindowMinutes: Int
    /// How long a reminder notification stays deliverable after it is due, when its subject sets no later bound.
    public let defaultValidityMinutes: Int
    /// Whether the daily brief's availability is notified (once per daily brief).
    public let notifyBriefAvailability: Bool
    /// The APNs provider, when configured; `nil` means pushes can only be dry runs.
    public let apns: APNsConfiguration?

    /// The R1 values of `NotificationSettings()`, with no APNs provider.
    public static let defaultValue: NotificationConfiguration = {
        let settings = NotificationSettings()
        return NotificationConfiguration(
            enabled: settings.enabled, timeSensitiveForUrgentDeadlines: false,
            urgentDeadlineWindowMinutes: settings.urgentDeadlineWindowMinutes,
            defaultValidityMinutes: settings.defaultValidityMinutes,
            notifyBriefAvailability: settings.notifyBriefAvailability, apns: nil)
    }()

    static func decode(_ section: ConfigSection?) -> NotificationConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return NotificationConfiguration(
            enabled: section.bool("enabled", default: defaults.enabled),
            timeSensitiveForUrgentDeadlines: section.bool(
                "timeSensitiveForUrgentDeadlines", default: defaults.timeSensitiveForUrgentDeadlines),
            urgentDeadlineWindowMinutes: section.integer(
                "urgentDeadlineWindowMinutes", default: defaults.urgentDeadlineWindowMinutes, in: 1...120),
            defaultValidityMinutes: section.integer(
                "defaultValidityMinutes", default: defaults.defaultValidityMinutes, in: 1...1440),
            notifyBriefAvailability: section.bool("notifyBriefAvailability", default: defaults.notifyBriefAvailability),
            apns: section.section("apns").flatMap(APNsConfiguration.decode))
    }
}
