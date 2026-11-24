// Core's signing public key as owner texts carry it (plan §8.1.1, §8.1.2 step 2).

import LisaCrypto
import LisaSyncProtocol

/// Core's P-256 signing public key, validated as canonical DER whose SHA-256 equals the separately carried full
/// fingerprint. Only this key verifies Core's application signatures during enrollment and re-anchoring; a TLS key,
/// CA, export key or a key first seen in an unverified response cannot supply it.
public struct CoreSigningIdentity: Hashable, Sendable {
    public let verifier: P256Verifier

    /// - Throws: `TrustError.nonCanonicalSigningKey` unless `spkiDER` is canonical P-256 DER, and
    ///   `.fingerprintMismatch` unless SHA-256 of exactly those bytes is `fingerprint`.
    public init(spkiDER: [UInt8], fingerprint: Digest256) throws(TrustError) {
        guard let parsed = try? P256Verifier(canonicalSPKI: spkiDER) else { throw .nonCanonicalSigningKey }
        guard parsed.fingerprint == fingerprint.bytes else { throw .fingerprintMismatch }
        verifier = parsed
    }

    public init(verifier: P256Verifier) {
        self.verifier = verifier
    }

    /// The canonical DER SubjectPublicKeyInfo.
    public var spkiDER: [UInt8] { verifier.spkiDER }

    /// SHA-256 of the DER, the fingerprint the administrative console shows in lowercase hexadecimal.
    public var fingerprint: Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: verifier.fingerprint)
    }
}
