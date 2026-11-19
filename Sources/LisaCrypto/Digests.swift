// SHA-256 digests and constant-time comparison through swift-crypto (REC-DEP-06); no in-house cryptography.

import Crypto
import Foundation

/// Hashing helpers. Credential verifiers are SHA-256 digests of high-entropy random tokens.
public enum Digests {
    /// The lower-case hexadecimal SHA-256 digest of `data`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The SHA-256 digest of UTF-8 `text`.
    public static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }

    /// The raw 32-byte SHA-256 digest.
    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Compares two byte strings in time that depends only on their lengths.
    public static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}
