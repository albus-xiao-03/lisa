// A P-256 signature-verification key accepted only in canonical DER form (plan §8.1.1, §8.1.2, §8.16.1).

import Crypto
import Foundation

/// A P-256 ECDSA public key for verifying raw 64-byte signatures.
///
/// It is created only from canonical DER: a SubjectPublicKeyInfo with `id-ecPublicKey`, the named curve secp256r1 and
/// an uncompressed point, which re-encodes to exactly the same bytes. Its fingerprint is the SHA-256 of those bytes,
/// the form Lisa compares the Core signing key by.
public struct P256Verifier: Sendable {
    /// The length of a canonical P-256 SubjectPublicKeyInfo with an uncompressed point.
    public static let canonicalSPKILength = 91

    let key: P256.Signing.PublicKey
    /// The canonical DER SubjectPublicKeyInfo.
    public let spkiDER: [UInt8]

    /// - Throws: `CryptoKeyError.nonCanonicalPublicKey` unless `der` is a canonical P-256 SubjectPublicKeyInfo.
    public init(canonicalSPKI der: [UInt8]) throws(CryptoKeyError) {
        guard der.count == Self.canonicalSPKILength,
            let parsed = try? P256.Signing.PublicKey(derRepresentation: der),
            Array(parsed.derRepresentation) == der
        else { throw .nonCanonicalPublicKey }
        key = parsed
        spkiDER = der
    }

    init(key: P256.Signing.PublicKey) {
        self.key = key
        spkiDER = Array(key.derRepresentation)
    }

    /// SHA-256 of the canonical DER.
    public var fingerprint: [UInt8] { Array(SHA256.hash(data: spkiDER)) }

    /// The fingerprint in lowercase hexadecimal, 64 digits.
    public var fingerprintHex: String { Digests.sha256Hex(Data(spkiDER)) }

    /// Whether `signature` is a valid raw (`r ‖ s`) P-256 ECDSA signature by this key over `message`.
    public func isValidSignature(_ signature: [UInt8], for message: [UInt8]) -> Bool {
        guard signature.count == 64,
            let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return false }
        return key.isValidSignature(parsed, for: message)
    }
}

extension P256Verifier: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.spkiDER == rhs.spkiDER }
    public func hash(into hasher: inout Hasher) { hasher.combine(spkiDER) }
}
