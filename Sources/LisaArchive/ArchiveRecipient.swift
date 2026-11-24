// The recipients an archive's payload key is sealed to (plan §8.6.6, §8.6.2).

import LisaCrypto
import LisaSyncProtocol

/// Who can open an archive.
public enum ArchiveRecipientKind: String, Hashable, Sendable, CaseIterable {
    /// Core's export key from the roster.
    case coreRoster = "core-roster"
    /// A Core export key the owner supplied before enrollment (§8.6.2).
    case ownerSuppliedCoreKey = "owner-supplied-core-key"
    /// This installation's own export key; nobody else can open it.
    case installationOnly = "installation-only"
}

/// One recipient: its kind, the SHA-256 of its export public key's canonical DER as key ID, and the payload key
/// sealed to it with HPKE (DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM).
public struct ArchiveRecipient: Hashable, Sendable {
    public let kind: ArchiveRecipientKind
    public let keyID: Digest256
    public let encapsulatedKey: [UInt8]
    public let sealedKey: [UInt8]

    public init(kind: ArchiveRecipientKind, keyID: Digest256, encapsulatedKey: [UInt8], sealedKey: [UInt8]) {
        self.kind = kind
        self.keyID = keyID
        self.encapsulatedKey = encapsulatedKey
        self.sealedKey = sealedKey
    }

    /// The key ID of an export public key.
    public static func keyID(of key: P256AgreementPublicKey) -> Digest256 {
        ArchiveDigest.keyID(ofSPKI: key.spkiDER)
    }

    /// The HPKE context binding a sealed payload key to one archive.
    static func info(archiveID: Identifier128) -> [UInt8] {
        Array("lisa-archive-v1 payload key\n".utf8) + archiveID.bytes
    }

    /// The HPKE authenticated data binding a sealed payload key to its recipient entry.
    static func authenticatedData(kind: ArchiveRecipientKind, keyID: Digest256) -> [UInt8] {
        Array(kind.rawValue.utf8) + [0x00] + keyID.bytes
    }
}
