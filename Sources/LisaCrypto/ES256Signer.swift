// ES256 (ECDSA P-256 with SHA-256) signing for JWS provider tokens, through swift-crypto.

import Crypto
import Foundation

/// Why a signing key could not be used.
public enum SigningKeyError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidKey

    public var description: String { "the signing key is not a valid PEM-encoded P-256 private key" }
}

/// Signs data with a P-256 private key. The key never leaves this value and is never described or logged.
public struct ES256Signer: Sendable {
    private let key: P256.Signing.PrivateKey

    /// Creates a signer from a PEM-encoded PKCS#8 P-256 private key (for example an APNs `.p8` key).
    public init(pemPrivateKey: String) throws {
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: pemPrivateKey)
        } catch {
            throw SigningKeyError.invalidKey
        }
    }

    /// The JWS ES256 signature of `data`: the 64-byte raw `r || s` form (RFC 7518 §3.4).
    public func sign(_ data: Data) throws -> Data {
        try key.signature(for: data).rawRepresentation
    }

    /// The public key in PEM form, for verification and diagnostics.
    public var publicKeyPEM: String { key.publicKey.pemRepresentation }

    /// Verifies a raw `r || s` signature with a PEM public key.
    public static func verify(signature: Data, of data: Data, publicKeyPEM: String) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(pemRepresentation: publicKeyPEM),
            let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return false }
        return publicKey.isValidSignature(parsed, for: data)
    }
}
