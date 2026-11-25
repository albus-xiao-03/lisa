// Core's export keys (plan §8.1.1, §8.1.4 export-key rotation): the current P-256 agreement key, whose public half
// the roster carries, and every retired one, kept so an archive sealed to an earlier roster still opens. An archive
// names the key it was sealed to by its key ID, SHA-256 of the public key's SubjectPublicKeyInfo DER, and the ring
// gives the matching private key. Rotating announces the new public key through the next roster (`CoreTrust` signs a
// new version whenever the export key it is given changes); the private keys are owner secrets (§8.11.2).

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// The current export key and the retired ones.
public struct CoreExportKeys: Sendable {
    public let current: P256AgreementKey
    /// Oldest first.
    public let retired: [P256AgreementKey]

    public init(current: P256AgreementKey, retired: [P256AgreementKey] = []) {
        self.current = current
        self.retired = retired
    }

    /// The public key the roster announces.
    public var announced: P256AgreementPublicKey { current.publicKey }

    /// After a rotation to `next`: the old current key is retired and kept.
    public func rotated(to next: P256AgreementKey) -> CoreExportKeys {
        CoreExportKeys(current: next, retired: retired + [current])
    }

    /// The private key an archive names, current or retired; none for a key Core never held.
    public func key(for keyID: Digest256) -> P256AgreementKey? {
        ([current] + retired.reversed()).first { Self.keyID(of: $0.publicKey) == keyID }
    }

    /// SHA-256 of the public key's SubjectPublicKeyInfo DER.
    public static func keyID(of key: P256AgreementPublicKey) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(key.spkiDER))))
    }
}
