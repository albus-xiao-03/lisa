// Errors of notification responses: unreadable payloads, unknown or unoffered actions and unusable identifiers.

import Foundation
import LisaAPIContract

/// Why a notification response could not be handled.
public enum NotificationActionError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The notification carries no readable `lisa` payload object.
    case unreadablePayload
    /// The payload's schema version is not the one this client acts on.
    case unsupportedPayloadVersion(Int)
    /// The action identifier is neither `open` nor a Lisa action.
    case unknownAction(String)
    /// The notification's category does not offer the action.
    case actionNotOffered(action: NotificationActionID, category: NotificationCategoryID)
    /// The installation or notification identifier cannot form a valid request ID.
    case unusableIdentifiers(notificationID: String)
    /// No notification identifiers were given.
    case noReceipts

    public var description: String {
        switch self {
        case .unreadablePayload: "the notification has no readable Lisa payload"
        case .unsupportedPayloadVersion(let version): "the notification payload uses unsupported version \(version)"
        case .unknownAction(let identifier): "\"\(identifier)\" is not a Lisa notification action"
        case .actionNotOffered(let action, let category):
            "\(category.rawValue) notifications do not offer \(action.rawValue)"
        case .unusableIdentifiers(let notificationID):
            "notification \(notificationID) cannot be given a valid request ID"
        case .noReceipts: "no notification identifiers were given"
        }
    }
}
