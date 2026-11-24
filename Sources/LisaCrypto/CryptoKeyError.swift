// Why a key, signature or sealed message was refused by LisaCrypto's R2 primitives (plan §7.2.2, §8.1.1).

/// A key or cryptographic input that LisaCrypto refused.
public enum CryptoKeyError: Error, Hashable, Sendable {
    /// The private key bytes are not a valid P-256 scalar.
    case invalidPrivateKey
    /// The public key is not a P-256 SubjectPublicKeyInfo with the named curve and an uncompressed point, or its DER
    /// does not survive a byte-for-byte canonical round trip.
    case nonCanonicalPublicKey
    /// The signature is not 64 raw bytes.
    case invalidSignatureLength(Int)
    /// Signing failed inside the cryptography library.
    case signingFailed
    /// Key agreement or key derivation failed (for example a peer key of low order).
    case agreementFailed
    /// An output length the derivation cannot produce.
    case invalidOutputLength(Int)
    /// HPKE sealing failed.
    case sealFailed
    /// HPKE opening failed: wrong key, wrong context, or altered bytes.
    case openFailed
}
