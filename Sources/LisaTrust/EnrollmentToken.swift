// The enrollment token and its one hash function (plan §8.1.2 step 1).

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// A 32-byte single-use enrollment token. Core stores only `tokenHash`; the owner text carries the token as unpadded
/// base64url. `description` never shows the bytes.
public struct EnrollmentToken: Hashable, Sendable, CustomStringConvertible {
    public static let byteCount = 32
    static let hashLabel = Array("lisa-enroll-token-v1".utf8)

    public let bytes: [UInt8]

    /// - Throws: `TrustError.invalidToken` unless `bytes` has exactly 32 bytes.
    public init(bytes: [UInt8]) throws(TrustError) {
        guard bytes.count == Self.byteCount else { throw .invalidToken }
        self.bytes = bytes
    }

    /// The token carried as unpadded base64url; any other length or spelling is refused.
    public init(payloadText: String) throws(TrustError) {
        guard let decoded = try? StrictBase64URL.decode(payloadText) else { throw .invalidToken }
        try self.init(bytes: decoded)
    }

    /// A new random token.
    public static func random() -> EnrollmentToken {
        EnrollmentToken(unchecked: [UInt8](RandomTokens.bytes(byteCount)))
    }

    init(unchecked bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The token as unpadded base64url.
    public var payloadText: String { StrictBase64URL.encode(bytes) }

    /// `SHA-256(ASCII "lisa-enroll-token-v1" ‖ 0x00 ‖ token)`, computed the same way at issuance and verification.
    public var tokenHash: [UInt8] {
        [UInt8](Digests.sha256(Data(Self.hashLabel + [0x00] + bytes)))
    }

    public var description: String { "EnrollmentToken(redacted)" }
}
