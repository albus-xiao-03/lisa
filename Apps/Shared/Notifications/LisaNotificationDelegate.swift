// The notification center's delegate: responses go to the notification-action handler, durably queued first, and a
// notification that arrives in the foreground is shown as it would be in the background.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import UserNotifications

/// Handles responses to Lisa's notifications and their presentation in the foreground (NOTIFY-05, plan §6.5).
///
/// - Opening a notification, by tapping it or choosing Open, opens the app on its item through `opened`; nothing is
///   submitted.
/// - Acknowledge, snooze and complete go to `NotificationActionHandler`, which writes the action to the durable queue
///   first, with the request identity (installation, notification, action), then tries to submit it within
///   `timeLimit`; otherwise it stays pending and the app shows it until the host confirms it. The system's completion
///   handler runs when the method returns, so the time limit must stay within the time the system allows a
///   background launch.
/// - A notification that arrives while the app is in the foreground is presented as a banner, in the list and with
///   its sound, as it would be in the background; the system's settings, Focus and preview settings still decide what
///   appears.
/// - With `recordsReceipts` (paired devices), every notification presented in the foreground, opened, acted on or
///   still listed gets a receipt, the host's only evidence of display. The Mac's embedded host records its own local
///   notifications, so it turns receipts off.
///
/// The system may call the delegate on any thread, so it holds only immutable, sendable state and its methods are
/// nonisolated.
final class LisaNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let handler: NotificationActionHandler
    private let receipts: NotificationReceiptRecorder?
    private let timeLimit: Duration
    private let opened: @MainActor @Sendable (LisaPushData) -> Void

    /// - Parameters:
    ///   - handler: the app's notification-action handler, over its single queue.
    ///   - recordsReceipts: whether presented notifications get receipts (paired devices only).
    ///   - timeLimit: how long an action tries to reach the host before it stays pending.
    ///   - opened: shows a notification's item in the app.
    init(
        handler: NotificationActionHandler, recordsReceipts: Bool, timeLimit: Duration,
        opened: @escaping @MainActor @Sendable (LisaPushData) -> Void
    ) {
        self.handler = handler
        receipts = recordsReceipts ? NotificationReceiptRecorder(handler: handler) : nil
        self.timeLimit = timeLimit
        self.opened = opened
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let subject = NotificationUserInfo.subject(of: notification.request.content.userInfo)
        if let receipts, let subject {
            let settings = await center.notificationSettings()
            if settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled {
                await receipts.record([subject.notificationID])
            }
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let identifier = Self.lisaIdentifier(forSystemIdentifier: response.actionIdentifier),
            let payload = NotificationUserInfo.json(from: response.notification.request.content.userInfo),
            let outcome = try? await handler.handle(
                payloadJSON: payload, actionIdentifier: identifier, timeLimit: timeLimit)
        else { return }
        await receipts?.record([outcome.subject.notificationID])
        if outcome.opensItem { await opened(outcome.subject) }
    }

    /// Records receipts for the Lisa notifications still listed in Notification Center, which the system presented
    /// while the app was not running. Call it at launch and on each return to the foreground.
    func recordListedReceipts() async {
        guard let receipts else { return }
        let listed = await UNUserNotificationCenter.current().deliveredNotifications()
        let identifiers = listed.compactMap {
            NotificationUserInfo.subject(of: $0.request.content.userInfo)?.notificationID
        }
        guard !identifiers.isEmpty else { return }
        await receipts.record(identifiers)
    }

    /// The handler's identifier for the system's: the default action (a tap) opens; dismissal, which Lisa does not
    /// ask the system to report, is ignored; Lisa's own action identifiers pass through.
    static func lisaIdentifier(forSystemIdentifier identifier: String) -> String? {
        switch identifier {
        case UNNotificationDefaultActionIdentifier: return NotificationResponseAction.openIdentifier
        case UNNotificationDismissActionIdentifier: return nil
        default: return identifier
        }
    }
}
