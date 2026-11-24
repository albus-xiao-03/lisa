// Why a protected archive could not be written, parsed or opened (plan §8.6.6).

import LisaSyncProtocol

/// A refusal by the archive codec. None carries key material or payload bytes.
public enum ArchiveError: Error, Hashable, Sendable {
    /// Not a `lisa-archive` v1 container, or its sections are truncated or inconsistent.
    case malformedContainer(String)
    /// The header is not canonical or breaks a field rule.
    case malformedHeader(String)
    /// No recipient entry for the opener's key.
    case notARecipient
    /// The payload key or payload could not be decrypted: wrong key, or altered bytes.
    case decryptionFailed
    /// The archive names another dataset than the opener's.
    case wrongDataset
    /// A payload entry of an unknown type, an oversized entry or a truncated payload.
    case malformedEntries
    /// Sealing failed.
    case sealFailed
}
