// Device pairing, push registration, permission status, notification preferences and receipts (NOTIFY-02, API-02).

import Foundation

/// The kind of device a companion runs on.
public enum DeviceClassValue: String, Codable, Hashable, Sendable, CaseIterable {
    case iPhone
    case iPad
    case mac
}

/// The APNs environment of the app build.
public enum APNsEnvironmentValue: String, Codable, Hashable, Sendable, CaseIterable {
    case development
    case production
}

/// The notification permission a device reports.
public enum NotificationAuthorizationValue: String, Codable, Hashable, Sendable, CaseIterable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

/// `POST /v1/devices/pairing-codes` (owner on the host only).
public struct PairingCodeDTO: Codable, Hashable, Sendable {
    public var code: String
    public var expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

/// `POST /v1/devices/pair`, authenticated by the one-time pairing code.
public struct PairDeviceRequest: Codable, Hashable, Sendable {
    public var code: String
    /// A random identifier created at installation; a reinstall creates a new one and pairs again.
    public var installationID: String
    public var name: String
    public var deviceClass: DeviceClassValue
    public var appBundleID: String
    public var environment: APNsEnvironmentValue

    public init(
        code: String, installationID: String, name: String, deviceClass: DeviceClassValue, appBundleID: String,
        environment: APNsEnvironmentValue
    ) {
        self.code = code
        self.installationID = installationID
        self.name = name
        self.deviceClass = deviceClass
        self.appBundleID = appBundleID
        self.environment = environment
    }
}

/// The paired device and its credential. The credential is returned exactly once; store it in Keychain.
public struct PairDeviceResponse: Codable, Hashable, Sendable {
    public var device: DeviceDTO
    public var credential: String

    public init(device: DeviceDTO, credential: String) {
        self.device = device
        self.credential = credential
    }
}

/// `PUT /v1/devices/current/push-registration`. The token is accepted only from an authenticated registration.
public struct PushRegistrationRequest: Codable, Hashable, Sendable {
    /// The APNs device token as hexadecimal text.
    public var token: String
    public var environment: APNsEnvironmentValue
    /// The app's bundle identifier (APNs topic).
    public var topic: String

    public init(token: String, environment: APNsEnvironmentValue, topic: String) {
        self.token = token
        self.environment = environment
        self.topic = topic
    }
}

/// `PUT /v1/devices/current/notification-status`.
public struct NotificationStatusRequest: Codable, Hashable, Sendable {
    public var authorization: NotificationAuthorizationValue
    /// Further settings such as `timeSensitive`, `lockScreen` or `showPreviews` (short values only).
    public var settings: [String: String]

    public init(authorization: NotificationAuthorizationValue, settings: [String: String] = [:]) {
        self.authorization = authorization
        self.settings = settings
    }
}

/// This device's notification preferences.
public struct DeviceNotificationPreferencesDTO: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// Category names: `reminder`, `overdue`, `planBlock`, `eventProposal`, `commitmentChange`, `brief`.
    public var categories: [String]
    /// Opt-in: include a truncated item title in notifications.
    public var showTitles: Bool
    public var allowTimeSensitive: Bool
    public var revision: Int64

    public init(enabled: Bool, categories: [String], showTitles: Bool, allowTimeSensitive: Bool, revision: Int64) {
        self.enabled = enabled
        self.categories = categories
        self.showTitles = showTitles
        self.allowTimeSensitive = allowTimeSensitive
        self.revision = revision
    }
}

/// `PATCH /v1/devices/current/notification-preferences`. Omitted fields are unchanged.
public struct DeviceNotificationPreferencesPatch: Codable, Hashable, Sendable {
    public var expectedRevision: Int64
    public var enabled: Bool?
    public var categories: [String]?
    public var showTitles: Bool?
    public var allowTimeSensitive: Bool?

    public init(
        expectedRevision: Int64, enabled: Bool? = nil, categories: [String]? = nil, showTitles: Bool? = nil,
        allowTimeSensitive: Bool? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.enabled = enabled
        self.categories = categories
        self.showTitles = showTitles
        self.allowTimeSensitive = allowTimeSensitive
    }
}

/// `POST /v1/devices/current/notification-receipts`: notifications this device presented (opened or still listed).
/// A receipt is the only evidence that a notification reached a device.
public struct NotificationReceiptsRequest: Codable, Hashable, Sendable {
    /// The most notification IDs one request may carry; larger requests are refused.
    public static let maxNotificationIDs = 200
    public var notificationIDs: [String]

    public init(notificationIDs: [String]) {
        self.notificationIDs = notificationIDs
    }
}

/// A paired device as the API shows it: never its credential or push token.
public struct DeviceDTO: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var deviceClass: DeviceClassValue
    /// `active` or `revoked`.
    public var state: String
    /// `apns` or `local`.
    public var transport: String
    public var pairedAt: Date
    public var lastSeenAt: Date?
    public var authorization: NotificationAuthorizationValue
    /// `active`, `invalid`, `unregistered`, `replaced`, or `nil` when no token is registered.
    public var pushTokenState: String?
    public var canReceiveNotifications: Bool
    public var preferences: DeviceNotificationPreferencesDTO
    /// True for the device making the request.
    public var isCurrent: Bool

    public init(
        id: String, name: String, deviceClass: DeviceClassValue, state: String, transport: String, pairedAt: Date,
        lastSeenAt: Date?, authorization: NotificationAuthorizationValue, pushTokenState: String?,
        canReceiveNotifications: Bool, preferences: DeviceNotificationPreferencesDTO, isCurrent: Bool
    ) {
        self.id = id
        self.name = name
        self.deviceClass = deviceClass
        self.state = state
        self.transport = transport
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
        self.authorization = authorization
        self.pushTokenState = pushTokenState
        self.canReceiveNotifications = canReceiveNotifications
        self.preferences = preferences
        self.isCurrent = isCurrent
    }
}
