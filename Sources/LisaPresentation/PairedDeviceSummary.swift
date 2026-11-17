// One paired device as the settings screen shows it: name and kind, still paired or removed, and whether it can
// receive notifications and why not.

import Foundation
import LisaAPIContract

/// One paired device (UI-01: paired devices and notification status) in plain words: its name and kind, whether it
/// is still paired, and whether it can receive notifications and why not. The host never reports a device's
/// credential or push token.
public struct PairedDeviceSummary: Hashable, Sendable, Identifiable {
    /// The device's identifier.
    public var id: String
    /// The device's name.
    public var name: String
    /// The kind in words: "iPhone", "iPad" or "Mac".
    public var kindLabel: String
    /// Whether the device is still paired.
    public var isActive: Bool
    /// Whether this is the device making the request.
    public var isCurrent: Bool
    /// When it was paired.
    public var pairedAt: Date
    /// When it last reached the host.
    public var lastSeenAt: Date?
    /// Whether notifications can be routed to it now.
    public var canReceiveNotifications: Bool
    /// Whether its notifications are turned on in its preferences.
    public var notificationsEnabled: Bool
    /// The notification permission the device reported.
    public var authorization: NotificationAuthorizationValue
    /// Whether it can receive notifications, or why not.
    public var notificationStatus: String

    /// The summary of `device`.
    public init(_ device: DeviceDTO) {
        id = device.id
        name = device.name
        kindLabel =
            switch device.deviceClass {
            case .iPhone: "iPhone"
            case .iPad: "iPad"
            case .mac: "Mac"
            }
        isActive = device.state == "active"
        isCurrent = device.isCurrent
        pairedAt = device.pairedAt
        lastSeenAt = device.lastSeenAt
        canReceiveNotifications = device.canReceiveNotifications
        notificationsEnabled = device.preferences.enabled
        authorization = device.authorization
        notificationStatus = Self.notificationStatus(device)
    }

    /// The device in one phrase for assistive technologies.
    public var accessibilityLabel: String {
        "\(name), \(kindLabel)\(isCurrent ? ", this device" : ""), \(notificationStatus)"
    }

    /// When the device last reached the host, in words such as "Last seen 2 hours ago", or that it has not yet.
    public func lastSeenPhrase(at now: Date) -> String {
        guard let lastSeenAt else { return "Not seen yet." }
        return "Last seen \(AgePhrase.english(now.timeIntervalSince(lastSeenAt))) ago."
    }

    private static func notificationStatus(_ device: DeviceDTO) -> String {
        guard device.state == "active" else { return "Removed. It can no longer reach Lisa." }
        if device.canReceiveNotifications { return "Receives notifications." }
        if !device.preferences.enabled { return "Notifications are turned off for this device." }
        guard NotificationPermissionStatus(authorization: device.authorization).allowsNotifications else {
            return "Notifications aren't allowed on this device (\(permission(device.authorization)))."
        }
        guard device.transport == "apns" else { return "It can't receive notifications right now." }
        switch device.pushTokenState {
        case nil: return "It hasn't registered for push notifications yet."
        case "invalid": return "Its push registration is no longer valid; opening the app registers it again."
        case "unregistered", "replaced":
            return "Its push registration was withdrawn; opening the app registers it again."
        default: return "It can't receive notifications right now."
        }
    }

    private static func permission(_ authorization: NotificationAuthorizationValue) -> String {
        switch authorization {
        case .notDetermined: "permission not asked yet"
        case .denied: "permission denied"
        case .authorized: "allowed"
        case .provisional: "delivered quietly"
        case .ephemeral: "allowed for now"
        case .unknown: "permission unknown"
        }
    }
}
