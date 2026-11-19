// The notification categories and actions Lisa registers at launch, from the shared contract's identifiers.

import Foundation
import LisaAPIContract
import LisaClient
import UserNotifications

/// Lisa's notification categories and actions (plan §6.5), registered at every launch.
///
/// | Category | Actions |
/// |---|---|
/// | Reminder, Overdue | Open, acknowledge, snooze, complete |
/// | Plan block | Open, acknowledge, snooze |
/// | Commitment change | Open, acknowledge |
/// | Event proposal, Brief | Open |
///
/// - Open (`NotificationResponseAction.openIdentifier`) brings the app to the foreground on the item, like tapping the
///   notification. Acknowledge and snooze run in the background. Complete runs in the background too and is
///   `.authenticationRequired`, so the system asks for the device to be unlocked first.
/// - Each category has a hidden-preview placeholder, shown when the system's "Show Previews" setting hides the body;
///   no option reveals the title or subtitle then.
/// - Text comes from `Localizable.strings` and is generic: it never contains the owner's content.
enum LisaNotificationCategories {
    /// Every category, built from `NotificationCategoryID` and `NotificationActionID`.
    static func all() -> Set<UNNotificationCategory> {
        Set(NotificationCategoryID.allCases.map(category(for:)))
    }

    /// Registers every category with `center`, replacing what an earlier launch registered.
    static func register(on center: UNUserNotificationCenter) {
        center.setNotificationCategories(all())
    }

    /// The category `id` with its actions and hidden-preview placeholder.
    static func category(for id: NotificationCategoryID) -> UNNotificationCategory {
        let open = UNNotificationAction(
            identifier: NotificationResponseAction.openIdentifier, title: localized("LISA_ACTION_OPEN"),
            options: [.foreground])
        return UNNotificationCategory(
            identifier: id.rawValue, actions: [open] + id.actions.map(action(for:)), intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: localized("\(id.rawValue)_HIDDEN_PREVIEW"), options: [])
    }

    /// The action `id`: acknowledge and snooze in the background, complete only once the device is unlocked.
    static func action(for id: NotificationActionID) -> UNNotificationAction {
        switch id {
        case .acknowledge:
            return UNNotificationAction(
                identifier: id.rawValue, title: localized("LISA_ACTION_ACKNOWLEDGE"), options: [])
        case .snooze:
            return UNNotificationAction(identifier: id.rawValue, title: localized("LISA_ACTION_SNOOZE"), options: [])
        case .complete:
            return UNNotificationAction(
                identifier: id.rawValue, title: localized("LISA_ACTION_COMPLETE"), options: [.authenticationRequired])
        }
    }

    /// The text for `key` in the app's `Localizable.strings`.
    private static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}
