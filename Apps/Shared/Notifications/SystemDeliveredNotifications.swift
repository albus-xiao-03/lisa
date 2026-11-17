// Removes this app's delivered notifications from Notification Center, for a device that was removed or unpaired.

import Foundation
import LisaPresentation
import UserNotifications

/// Clears the notifications already delivered to this device (plan §6.3), with its cached data, when the host removes
/// the device or the owner unpairs it. Every notification of the app is Lisa's, so all of them are removed.
struct SystemDeliveredNotifications: DeliveredNotificationRemoving {
    func removeAllDeliveredNotifications() async {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
