// A delivered notification's user info as the JSON the notification-action handler reads, and the Lisa item in it.

import Foundation
import LisaAPIContract

/// Reads a delivered notification's user info: the APNs payload of a push, or the same `lisa` object in a local
/// notification of the Mac's embedded host (plan §6.7). The content is untrusted and is only parsed, never executed.
public enum NotificationUserInfo {
    /// The most bytes of user info converted. APNs payloads are at most 4 KiB.
    public static let maxBytes = 16_384

    /// The user info as JSON with its string keys, or `nil` when it is not JSON-compatible or larger than `maxBytes`.
    public static func json(from userInfo: [AnyHashable: Any]) -> Data? {
        var object: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let name = key.base as? String else { continue }
            object[name] = value
        }
        guard JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            data.count <= maxBytes
        else { return nil }
        return data
    }

    /// The Lisa item a notification is about, or `nil` for a notification without a readable `lisa` object.
    public static func subject(of userInfo: [AnyHashable: Any]) -> LisaPushData? {
        json(from: userInfo).flatMap(PushPayload.lisaData(fromJSON:))
    }
}
