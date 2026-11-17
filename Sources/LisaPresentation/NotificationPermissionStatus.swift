// The system's notification permission for this app, as the app reads it and reports it to the host.

import Foundation
import LisaAPIContract

/// The system's notification permission and related settings for this app (NOTIFY-05), as read at launch and on each
/// return to the foreground.
public struct NotificationPermissionStatus: Hashable, Sendable {
    /// The most settings one report carries (the host's limit).
    public static let maxReportedSettings = 20
    /// The longest setting name or value reported.
    public static let maxSettingLength = 64

    /// Whether the person allowed notifications: authorized, denied, provisional, not determined, ephemeral or unknown.
    public var authorization: NotificationAuthorizationValue
    /// Further system settings with short values, such as `timeSensitive`, `lockScreen` or `showPreviews`.
    public var settings: [String: String]

    /// A status with `authorization` and `settings`.
    public init(authorization: NotificationAuthorizationValue, settings: [String: String] = [:]) {
        self.authorization = authorization
        self.settings = settings
    }

    /// Whether notifications can be shown: authorized, provisional or ephemeral.
    public var allowsNotifications: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied, .unknown: false
        }
    }

    /// The report for the host: at most `maxReportedSettings` settings in name order, names and values cut to
    /// `maxSettingLength` characters.
    var request: NotificationStatusRequest {
        var reported: [String: String] = [:]
        for name in settings.keys.sorted().prefix(Self.maxReportedSettings) {
            guard let value = settings[name] else { continue }
            reported[String(name.prefix(Self.maxSettingLength))] = String(value.prefix(Self.maxSettingLength))
        }
        return NotificationStatusRequest(authorization: authorization, settings: reported)
    }
}
