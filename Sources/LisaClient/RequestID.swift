// Request identities (API-03): the accepted form, random IDs and the deterministic notification-action form.

import Foundation
import LisaAPIContract

/// `Lisa-Request-ID` values: 8 to 128 characters from `A-Z`, `a-z`, `0-9`, `.`, `_`, `:` and `-`.
public enum RequestID {
    /// The shortest accepted request ID.
    public static let minimumLength = 8
    /// The longest accepted request ID.
    public static let maximumLength = 128

    /// A new random request ID: a lowercase UUID.
    public static func random() -> String {
        UUID().uuidString.lowercased()
    }

    /// Whether `value` matches `^[A-Za-z0-9._:-]{8,128}$`.
    public static func isValid(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        return (minimumLength...maximumLength).contains(scalars.count) && scalars.allSatisfy(isAllowed)
    }

    /// The request ID of an action chosen on a delivered notification: `na:<installation>:<notification>:<action>`
    /// (plan §6.5). The system may invoke the action handler more than once; the same installation, notification and
    /// action always give the same ID, so the host applies the action once.
    ///
    /// - Returns: `nil` when an identifier is empty or contains `:`, or when the result is not a valid request ID, for
    ///   example because it would be longer than 128 characters.
    public static func notificationAction(
        installationID: String, notificationID: String, action: NotificationActionID
    ) -> String? {
        guard isComponent(installationID), isComponent(notificationID) else { return nil }
        let value = "na:\(installationID):\(notificationID):\(action.rawValue)"
        return isValid(value) ? value : nil
    }

    /// Whether `value` can be one `:`-separated part of a derived request ID without making it ambiguous.
    private static func isComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(":")
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", ".", "_", ":", "-": true
        default: false
        }
    }
}
