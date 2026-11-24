// A software P-256 signing key producing raw 64-byte signatures (plan §8.16.1): Core's signing key, and harnesses.
// Device keys on Apple platforms live in the Secure Enclave or Keychain behind LisaTrust's `KeyStore` port instead.

import Crypto

/// A P-256 ECDSA private key whose signatures are raw 64-byte `r ‖ s` values.
public struct P256RawSigner: Sendable {
    let key: P256.Signing.PrivateKey

    /// A new random key.
    public init() {
        key = P256.Signing.PrivateKey()
    }

    /// A key from its 32-byte raw scalar.
    /// - Throws: `CryptoKeyError.invalidPrivateKey` for bytes that are not a valid P-256 scalar.
    public init(rawPrivateKey: [UInt8]) throws(CryptoKeyError) {
        guard let parsed = try? P256.Signing.PrivateKey(rawRepresentation: rawPrivateKey) else {
            throw .invalidPrivateKey
        }
        key = parsed
    }

    /// The 32-byte raw scalar, for writing the key to an owner-only secret file.
    public var rawPrivateKey: [UInt8] { Array(key.rawRepresentation) }

    /// The matching verification key.
    public var verifier: P256Verifier { P256Verifier(key: key.publicKey) }

    /// The raw 64-byte signature over `message`, exactly as given; callers prefix their signing domain (§8.16.1).
    public func signature(for message: [UInt8]) throws(CryptoKeyError) -> [UInt8] {
        guard let signed = try? key.signature(for: message) else { throw .signingFailed }
        return Array(signed.rawRepresentation)
    }
}
