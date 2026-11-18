// A paired companion installation: credential verifier, APNs token lifecycle, permission status and preferences.

import Foundation
import LisaRedaction

/// The kind of device a companion runs on.
public enum DeviceClass: String, Codable, Sendable, CaseIterable {
    case iPhone
    case iPad
    case mac
}

/// The APNs environment a token belongs to. A token is only ever sent to its own environment.
public enum APNsEnvironment: String, Codable, Sendable, CaseIterable {
    case development
    case production
}

/// The system notification permission a device last reported.
public enum NotificationAuthorization: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    /// Whether the device can currently display Lisa's notifications.
    public var allowsDisplay: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

/// How notifications reach this installation.
public enum NotificationTransportKind: String, Codable, Sendable {
    /// Remote delivery through APNs.
    case apns
    /// Local notifications posted by the host running in the same app (the Mac app's embedded host).
    case local
}

/// The state of a push token.
public enum PushTokenState: String, Codable, Sendable {
    case active
    case invalid
    case unregistered
    case replaced
}

/// An APNs device token bound to an authenticated registration. Possessing it authenticates nothing.
public struct PushTokenRecord: Hashable, Codable, Sendable {
    public var token: Sensitive<String>
    public var environment: APNsEnvironment
    public var topic: String
    public var registeredAt: Date
    public var state: PushTokenState
    public var stateChangedAt: Date?

    public init(token: String, environment: APNsEnvironment, topic: String, registeredAt: Date) {
        self.token = Sensitive(token)
        self.environment = environment
        self.topic = topic
        self.registeredAt = registeredAt
        self.state = .active
        self.stateChangedAt = nil
    }
}

/// Per-device notification preferences.
public struct DeviceNotificationPreferences: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var categories: Set<NotificationCategory>
    /// Opt-in: include a truncated item title in the notification. Off by default.
    public var showTitles: Bool
    /// Whether this device accepts the Time Sensitive level for urgent deadlines.
    public var allowTimeSensitive: Bool

    public init(
        enabled: Bool = true, categories: Set<NotificationCategory> = Set(NotificationCategory.allCases),
        showTitles: Bool = false, allowTimeSensitive: Bool = true
    ) {
        self.enabled = enabled
        self.categories = categories
        self.showTitles = showTitles
        self.allowTimeSensitive = allowTimeSensitive
    }
}

/// Whether a registration can still be used.
public enum DeviceState: String, Codable, Sendable {
    case active
    case revoked
}

/// One paired installation. The host stores only a verifier of the device credential.
public struct DeviceRegistration: Entity {
    public static let collectionName = "devices"
    public let id: DeviceID
    public var revision: Revision
    public var updatedAt: Date
    public var installationID: String
    public var name: String
    public var deviceClass: DeviceClass
    public var appBundleID: String
    public var environment: APNsEnvironment
    public var transport: NotificationTransportKind
    /// SHA-256 verifier of the device credential, hex encoded.
    public var credentialVerifier: String
    public var state: DeviceState
    public var pairedAt: Date
    public var revokedAt: Date?
    public var lastSeenAt: Date?
    public var pushToken: PushTokenRecord?
    /// Earlier tokens, newest first, at most five. Provider reports are judged against the current token only.
    public var tokenHistory: [PushTokenRecord]
    public var authorization: NotificationAuthorization
    public var authorizationReportedAt: Date?
    /// Further reported settings, such as lock-screen or Time Sensitive status.
    public var reportedSettings: [String: String]
    public var preferences: DeviceNotificationPreferences

    public init(
        id: DeviceID = .random(), installationID: String, name: String, deviceClass: DeviceClass,
        appBundleID: String, environment: APNsEnvironment, transport: NotificationTransportKind,
        credentialVerifier: String, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.installationID = installationID
        self.name = name
        self.deviceClass = deviceClass
        self.appBundleID = appBundleID
        self.environment = environment
        self.transport = transport
        self.credentialVerifier = credentialVerifier
        self.state = .active
        self.pairedAt = now
        self.revokedAt = nil
        self.lastSeenAt = nil
        self.pushToken = nil
        self.tokenHistory = []
        self.authorization = .notDetermined
        self.authorizationReportedAt = nil
        self.reportedSettings = [:]
        self.preferences = DeviceNotificationPreferences()
    }

    /// Whether notifications can be routed to this device at all.
    public var canReceiveNotifications: Bool {
        guard state == .active, preferences.enabled, authorization.allowsDisplay else { return false }
        switch transport {
        case .local: return true
        case .apns: return pushToken?.state == .active
        }
    }
}
