// The content of one local notification, from the host's neutral presentation: the generic localized title and body
// (or the titled body when this Mac opted in to titles), the category, thread and interruption level, and the same
// `lisa` object an APNs payload carries, which the notification-action handler reads.

import Foundation
import LisaAPIContract
import LisaDomain
import LisaPorts
import UserNotifications

/// Builds the notification content for a `NotificationPresentation` (plan §6.7, NOTIFY-06, D-38), as the APNs payload
/// builder does for a push:
/// - the title is `titleKey` and the body `bodyKey`, localized from `Localizable.strings`; with an item title (present
///   only when this Mac's installation opted in to titles) the body is the category's `_BODY_TITLED` format with the
///   title as its only argument;
/// - the category, the thread and the interruption level (passive, active or Time Sensitive, never critical) come from
///   the presentation; passive notifications make no sound;
/// - the user info holds only the `lisa` object of opaque identifiers, encoded with the shared contract's keys.
enum LocalNotificationContent {
    /// Why a presentation can't be shown. The message names the category, never the owner's content.
    struct Unusable: Error, CustomStringConvertible {
        let description: String
    }

    /// The content for `presentation`.
    static func make(for presentation: NotificationPresentation) throws(Unusable) -> UNNotificationContent {
        guard let category = NotificationCategoryID(rawValue: presentation.categoryIdentifier),
            let kind = hostKind(of: category)
        else {
            throw Unusable(description: "the notification category \(presentation.categoryIdentifier) is not known")
        }
        let content = UNMutableNotificationContent()
        content.title = localized(presentation.titleKey)
        content.body = body(of: presentation, category: category)
        content.categoryIdentifier = category.rawValue
        content.threadIdentifier = presentation.threadIdentifier
        switch presentation.level {
        case .passive:
            content.interruptionLevel = .passive
        case .active:
            content.interruptionLevel = .active
            content.sound = .default
        case .timeSensitive:
            content.interruptionLevel = .timeSensitive
            content.sound = .default
        }
        let lisa = LisaPushData(
            kind: kind, notificationID: presentation.notificationID, subjectKind: presentation.subjectKind,
            subjectID: presentation.subjectID, subjectRevision: presentation.subjectRevision)
        guard let data = try? JSONEncoder().encode(lisa), let object = try? JSONSerialization.jsonObject(with: data)
        else { throw Unusable(description: "the notification's identifiers could not be encoded") }
        content.userInfo = ["lisa": object]
        return content
    }

    /// The host's category name sent as `lisa.kind`, such as `reminder`, found through the contract's own mapping.
    private static func hostKind(of category: NotificationCategoryID) -> String? {
        NotificationCategory.allCases.first { NotificationCategoryID(kind: $0.rawValue) == category }?.rawValue
    }

    /// The generic body, or the titled body when the presentation carries an item title and the category has a
    /// titled format.
    private static func body(of presentation: NotificationPresentation, category: NotificationCategoryID) -> String {
        let generic = localized(presentation.bodyKey)
        guard presentation.bodyKey == category.bodyKey,
            let title = presentation.itemTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return generic }
        let format = localized(category.titledBodyKey)
        guard format != category.titledBodyKey, format.components(separatedBy: "%@").count == 2 else { return generic }
        return String(format: format, title)
    }

    /// The text for `key` in the app's `Localizable.strings`; the key itself when it has none.
    private static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}
