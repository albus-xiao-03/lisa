// The seam to the system's notification permission, which the Apple apps implement with UserNotifications.

import Foundation

/// Reads and requests the system's notification permission for this app. The Apple apps implement it with
/// UserNotifications; nothing here decides what the system allows.
public protocol NotificationPermissionReading: Sendable {
    /// The current permission and settings.
    func currentStatus() async -> NotificationPermissionStatus
    /// Asks the person to allow notifications and returns the permission afterwards. Lisa asks only when pairing
    /// offers to turn notifications on (plan §6.5).
    func requestAuthorization() async throws -> NotificationPermissionStatus
}
