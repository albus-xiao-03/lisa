// Minimal, privacy-conscious notification content (NOTIFY-06): generic localized text unless a device opts in.

import Foundation
import LisaDomain

/// What a notification shows. Keys are localized on the device, so the payload carries no item text by default.
public struct NotificationContent: Hashable, Sendable {
    public var titleKey: String
    public var bodyKey: String
    /// A truncated item title, present only for devices that opted in to titles.
    public var itemTitle: String?
    public var categoryIdentifier: String
    public var threadIdentifier: String
}

/// Content rules.
public enum NotificationContentPolicy {
    /// The longest item title ever placed in a payload.
    public static let maxTitleCharacters = 60

    public static func content(for intent: NotificationIntent, showTitle: Bool) -> NotificationContent {
        let base: String =
            switch intent.category {
            case .reminder: "LISA_REMINDER"
            case .overdue: "LISA_OVERDUE"
            case .planBlock: "LISA_PLAN_BLOCK"
            case .eventProposal: "LISA_EVENT_PROPOSAL"
            case .commitmentChange: "LISA_COMMITMENT_CHANGE"
            case .brief: "LISA_BRIEF"
            }
        var title: String?
        if showTitle, let hint = intent.titleHint {
            let flattened = hint.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespaces)
            title =
                flattened.count > maxTitleCharacters
                ? String(flattened.prefix(maxTitleCharacters - 1)) + "…" : flattened
        }
        return NotificationContent(
            titleKey: "\(base)_TITLE", bodyKey: "\(base)_BODY", itemTitle: title, categoryIdentifier: base,
            threadIdentifier: intent.subject.key)
    }
}
