// The embedded host's local-notification transport (plan §6.5): each delivery is posted to Notification Center when
// the host delivers it, with no trigger and nothing scheduled ahead, and the result says truthfully what happened.

import Foundation
import LisaPorts
import UserNotifications

/// Presents the embedded host's notifications on this Mac (`LocalNotificationTransport`, plan §6.5, NOTIFY-05).
///
/// - The host calls it when a delivery is due. The request has no trigger, so the system presents it at once; the app
///   never schedules a notification ahead, so the host stays the only scheduler.
/// - The request's identifier is the delivery's identifier, so presenting a retried delivery replaces the earlier
///   request instead of adding a second notification.
/// - Results: `rejected` when the system doesn't allow Lisa's notifications (retrying would not help until the owner
///   allows them); `notSent` when the system did not take the request; `confirmedDelivered` when the notification is
///   then listed in Notification Center; otherwise `accepted`, because the system took it but may still hold it back,
///   for example for Focus or a scheduled summary. A notification is never reported as displayed without evidence.
struct UserNotificationTransport: LocalNotificationTransport {
    func present(_ presentation: NotificationPresentation, deliveryID: String) async -> TransportResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return Self.notAllowed
        }
        let content: UNNotificationContent
        do throws(LocalNotificationContent.Unusable) {
            content = try LocalNotificationContent.make(for: presentation)
        } catch {
            return .rejected(reason: error.description, invalidatesRecipient: false, providerTimestamp: nil)
        }
        let request = UNNotificationRequest(identifier: deliveryID, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            if (error as? UNError)?.code == .notificationsNotAllowed { return Self.notAllowed }
            return .notSent(reason: "macOS did not take the notification: \(error.localizedDescription)")
        }
        let listed = await center.deliveredNotifications()
        if listed.contains(where: { $0.request.identifier == deliveryID }) {
            return .confirmedDelivered(providerReference: deliveryID)
        }
        return .accepted(providerReference: deliveryID)
    }

    private static let notAllowed = TransportResult.rejected(
        reason: "notifications for Lisa are not allowed on this Mac", invalidatesRecipient: false,
        providerTimestamp: nil)
}
