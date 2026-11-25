// The device's Core credential (plan §8.1.1): 256 random bits the device generates at enrollment. It travels as
// unpadded base64url in `Authorization: Bearer …`, and Core stores only its SHA-256 verifier. `description` never
// shows the bytes.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// A device's 256-bit Core credential.
public struct CoreCredential: Hashable, Sendable, CustomStringConvertible {
    public static let byteCount = 32

    public let bytes: [UInt8]

    /// - Throws: `TrustError.invalidToken` unless `bytes` has exactly 32 bytes.
    public init(bytes: [UInt8]) throws(TrustError) {
        guard bytes.count == Self.byteCount else { throw .invalidToken }
        self.bytes = bytes
    }

    /// The credential from its bearer text; any other length or spelling is refused.
    public init(bearerText: String) throws(TrustError) {
        guard let decoded = try? StrictBase64URL.decode(bearerText) else { throw .invalidToken }
        try self.init(bytes: decoded)
    }

    /// A new random credential.
    public static func random() -> CoreCredential {
        // Thirty-two random bytes always make a credential.
        try! CoreCredential(bytes: [UInt8](RandomTokens.bytes(byteCount)))
    }

    /// What `Authorization: Bearer` carries.
    public var bearerText: String { StrictBase64URL.encode(bytes) }

    /// SHA-256 of the credential's bytes: all Core keeps.
    public var verifier: Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(bytes))))
    }

    public var description: String { "CoreCredential(redacted)" }
}
