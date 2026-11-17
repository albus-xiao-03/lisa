// The `apns-priority` of an alert push (S10): 10 when the notification calls for the owner's prompt action,
// otherwise 5.

import LisaAPIContract
import LisaPorts

/// The two priorities Apple documents for alert pushes. Priority 1, which keeps the device asleep, is never used.
public enum APNsPriority: Int, Hashable, Sendable {
    /// "Send the notification immediately."
    case immediate = 10
    /// "Send the notification based on power considerations on the user's device"; may arrive grouped in bursts.
    case powerConsidered = 5

    /// Apple: "If the notification requires immediate action from the user, set notification priority to 10;
    /// otherwise use 5." Lisa reads that as: every Time Sensitive notification, and every active one whose category
    /// offers actions (acknowledge, snooze or complete). Passive notifications, the daily brief and event-proposal
    /// follow-ups, which only open the app, use 5.
    public static func forAlert(_ presentation: NotificationPresentation) -> APNsPriority {
        switch presentation.level {
        case .timeSensitive:
            return .immediate
        case .passive:
            return .powerConsidered
        case .active:
            guard let category = NotificationCategoryID(rawValue: presentation.categoryIdentifier) else {
                return .powerConsidered
            }
            return category.actions.isEmpty ? .powerConsidered : .immediate
        }
    }

    /// The header value.
    public var headerValue: String { String(rawValue) }
}
