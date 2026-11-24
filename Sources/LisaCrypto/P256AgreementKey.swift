// P-256 key agreement with HKDF-SHA256 derivation (plan §8.1.1 export keys, §8.7 Design A pair keys).

import Crypto
import Foundation

/// A P-256 key-agreement public key, accepted only as canonical DER (an uncompressed point on the named curve).
public struct P256AgreementPublicKey: Sendable {
    let key: P256.KeyAgreement.PublicKey
    /// The canonical DER SubjectPublicKeyInfo.
    public let spkiDER: [UInt8]

    /// - Throws: `CryptoKeyError.nonCanonicalPublicKey` unless `der` is a canonical P-256 SubjectPublicKeyInfo.
    public init(canonicalSPKI der: [UInt8]) throws(CryptoKeyError) {
        guard der.count == P256Verifier.canonicalSPKILength,
            let parsed = try? P256.KeyAgreement.PublicKey(derRepresentation: der),
            Array(parsed.derRepresentation) == der
        else { throw .nonCanonicalPublicKey }
        key = parsed
        spkiDER = der
    }

    init(key: P256.KeyAgreement.PublicKey) {
        self.key = key
        spkiDER = Array(key.derRepresentation)
    }
}

extension P256AgreementPublicKey: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.spkiDER == rhs.spkiDER }
    public func hash(into hasher: inout Hasher) { hasher.combine(spkiDER) }
}

/// A P-256 key-agreement private key.
public struct P256AgreementKey: Sendable {
    let key: P256.KeyAgreement.PrivateKey

    /// A new random key.
    public init() {
        key = P256.KeyAgreement.PrivateKey()
    }

    /// A key from its 32-byte raw scalar.
    public init(rawPrivateKey: [UInt8]) throws(CryptoKeyError) {
        guard let parsed = try? P256.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey) else {
            throw .invalidPrivateKey
        }
        key = parsed
    }

    /// The 32-byte raw scalar, for writing the key to an owner-only secret file.
    public var rawPrivateKey: [UInt8] { Array(key.rawRepresentation) }

    /// The matching public key.
    public var publicKey: P256AgreementPublicKey { P256AgreementPublicKey(key: key.publicKey) }

    /// HKDF-SHA256 over the ECDH shared secret with `peer`, with this salt and info.
    /// - Throws: `CryptoKeyError.agreementFailed` if the agreement fails, `.invalidOutputLength` for a length HKDF
    ///   cannot produce.
    public func derivedKey(
        with peer: P256AgreementPublicKey, salt: [UInt8], info: [UInt8], outputByteCount: Int
    ) throws(CryptoKeyError) -> [UInt8] {
        guard (1...(255 * 32)).contains(outputByteCount) else { throw .invalidOutputLength(outputByteCount) }
        guard let secret = try? key.sharedSecretFromKeyAgreement(with: peer.key) else { throw .agreementFailed }
        let derived = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: outputByteCount)
        return derived.withUnsafeBytes { Array($0) }
    }
}
