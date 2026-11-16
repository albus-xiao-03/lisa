// The response chosen on a delivered notification: opening it, or one of its category's Lisa actions.

import Foundation
import LisaAPIContract

/// What a person chose on a delivered notification.
public enum NotificationResponseAction: Hashable, Sendable {
    /// The notification itself, the default action: open the app on its item. Nothing is submitted.
    case open
    /// One of the category's actions.
    case action(NotificationActionID)

    /// The identifier the apps pass for opening a notification.
    public static let openIdentifier = "open"

    /// Parses an action identifier: `open`, or a `NotificationActionID` raw value. `nil` for anything else.
    public init?(identifier: String) {
        if identifier == Self.openIdentifier {
            self = .open
        } else if let action = NotificationActionID(rawValue: identifier) {
            self = .action(action)
        } else {
            return nil
        }
    }

    /// The identifier this response is parsed from.
    public var identifier: String {
        switch self {
        case .open: Self.openIdentifier
        case .action(let action): action.rawValue
        }
    }
}
