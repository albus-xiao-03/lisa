// The seam to the system's delivered notifications, which a removed or unpaired device clears (plan §6.3).

import Foundation

/// Removes this app's delivered notifications from the system's notification list. The Apple apps implement it with
/// UserNotifications; a removed or unpaired device clears its delivered notifications with its cached data
/// (plan §6.3).
public protocol DeliveredNotificationRemoving: Sendable {
    /// Removes every delivered Lisa notification.
    func removeAllDeliveredNotifications() async
}
