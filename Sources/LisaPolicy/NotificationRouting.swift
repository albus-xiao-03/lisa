// Routes a notification to every eligible paired device by default (NOTIFY-01), with per-device reasons.

import Foundation
import LisaDomain

/// The routing outcome for one device.
public struct RoutingDecision: Hashable, Sendable {
    public var deviceID: DeviceID
    public var deliver: Bool
    public var level: InterruptionLevel
    public var showTitle: Bool
    /// Why the device does not receive the notification, recorded on the suppressed delivery.
    public var suppressionReason: String?
}

/// Device routing. No device is silently chosen over another: every active registration gets a decision.
public enum NotificationRouting {
    public static func route(
        category: NotificationCategory, level: InterruptionLevel, devices: [DeviceRegistration]
    ) -> [RoutingDecision] {
        devices.filter { $0.state == .active }.sorted { $0.id < $1.id }.map { device in
            let preferences = device.preferences
            var reason: String?
            if !preferences.enabled {
                reason = "notifications are turned off for this device"
            } else if !device.authorization.allowsDisplay {
                reason = "the device reports notification permission as \(device.authorization.rawValue)"
            } else if !preferences.categories.contains(category) {
                reason = "this category is turned off for this device"
            } else if device.transport == .apns, device.pushToken?.state != .active {
                reason = "the device has no active push registration"
            }
            let effectiveLevel = level == .timeSensitive && !preferences.allowTimeSensitive ? .active : level
            return RoutingDecision(
                deviceID: device.id, deliver: reason == nil, level: effectiveLevel, showTitle: preferences.showTitles,
                suppressionReason: reason)
        }
    }
}
