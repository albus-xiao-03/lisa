// The system's notification permission for this app, read and requested through UserNotifications.

import Foundation
import LisaAPIContract
import LisaPresentation
import UserNotifications

/// Reads the system's notification permission and settings, and asks for permission (NOTIFY-05, plan §6.5).
///
/// - `requestAuthorization()` asks for alerts and sounds only: never badges, Critical Alerts or provisional delivery.
///   Lisa calls it only when pairing offers to turn notifications on. Time Sensitive needs no request; it is the
///   entitlement plus the person's setting, which is reported.
/// - The settings reported are `alert`, `sound`, `lockScreen`, `notificationCenter`, `alertStyle`, `showPreviews`,
///   `timeSensitive` and `scheduledDelivery`, with short values such as `enabled` or `whenAuthenticated`.
struct SystemNotificationPermissions: NotificationPermissionReading {
    func currentStatus() async -> NotificationPermissionStatus {
        Self.status(of: await UNUserNotificationCenter.current().notificationSettings())
    }

    func requestAuthorization() async throws -> NotificationPermissionStatus {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await currentStatus()
    }

    /// The permission and settings in `settings`.
    static func status(of settings: UNNotificationSettings) -> NotificationPermissionStatus {
        NotificationPermissionStatus(
            authorization: authorization(settings.authorizationStatus),
            settings: [
                "alert": text(settings.alertSetting),
                "sound": text(settings.soundSetting),
                "lockScreen": text(settings.lockScreenSetting),
                "notificationCenter": text(settings.notificationCenterSetting),
                "alertStyle": text(settings.alertStyle),
                "showPreviews": text(settings.showPreviewsSetting),
                "timeSensitive": text(settings.timeSensitiveSetting),
                "scheduledDelivery": text(settings.scheduledDeliverySetting),
            ])
    }

    private static func authorization(_ status: UNAuthorizationStatus) -> NotificationAuthorizationValue {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        #if os(iOS)
            case .ephemeral: return .ephemeral
        #endif
        @unknown default: return .unknown
        }
    }

    private static func text(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown"
        }
    }

    private static func text(_ style: UNAlertStyle) -> String {
        switch style {
        case .none: return "none"
        case .banner: return "banner"
        case .alert: return "alert"
        @unknown default: return "unknown"
        }
    }

    private static func text(_ previews: UNShowPreviewsSetting) -> String {
        switch previews {
        case .always: return "always"
        case .whenAuthenticated: return "whenAuthenticated"
        case .never: return "never"
        @unknown default: return "unknown"
        }
    }
}
