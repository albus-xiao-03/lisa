// The APNs device token as the host expects it: the token's bytes as lowercase hexadecimal digits.

import Foundation

/// Formats the device token the system returns at APNs registration for `PUT /v1/devices/current/push-registration`.
/// The token identifies this device to Apple's push service, so it is sent only to the host and never shown or logged.
public enum PushTokenText {
    /// The most token bytes accepted. Apple says not to assume a token length; the host accepts up to 1,024
    /// hexadecimal digits.
    public static let maxBytes = 512

    private static let digits = Array("0123456789abcdef".utf8)

    /// The token's bytes as lowercase hexadecimal digits, or `nil` for an empty token or one longer than `maxBytes`.
    public static func hex(_ token: Data) -> String? {
        guard !token.isEmpty, token.count <= maxBytes else { return nil }
        var text: [UInt8] = []
        text.reserveCapacity(token.count * 2)
        for byte in token {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}
