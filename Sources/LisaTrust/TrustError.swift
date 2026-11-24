// Why trust material was refused (plan §8.1.2, §8.1.4, §8.7).

import LisaSyncProtocol

/// A refusal by LisaTrust. Each case names the rule that failed; none carries a token or other secret.
public enum TrustError: Error, Hashable, Sendable {
    /// The owner text is longer than 4 KiB or not ASCII.
    case ownerTextTooLong(Int)
    case ownerTextNotASCII
    /// The text names an earlier format (`lisa-pair:3:`, `lisa-reanchor:1:`): ask the owner for current text.
    case outdatedOwnerText(prefix: String)
    /// The text is not an owner text of the expected kind.
    case unknownOwnerText
    /// The inner version disagrees with the prefix.
    case versionMismatch(expected: Int64, found: Int64)
    /// The payload is not strict base64url of a canonical JSON object.
    case payloadEncoding
    case payloadNotCanonical(CanonicalError)
    /// A field is missing, unknown, mistyped or malformed.
    case field(CanonicalFieldError)
    case invalidField(String)
    /// The typo checksum does not match.
    case checksumMismatch
    /// The Core signing key is not canonical P-256 DER, or its fingerprint is not the SHA-256 of those bytes.
    case nonCanonicalSigningKey
    case fingerprintMismatch
    /// The Core URL is not an `https` URL with a host and nothing else.
    case invalidCoreURL
    /// A `ca`-mode text lacks the owner-CA digest, or a `pin`-mode text carries one.
    case trustModeFields
    /// An enrollment token that is not exactly 32 bytes.
    case invalidToken
    /// A nearby session value of the wrong length, or a transcript naming other devices or nonces.
    case invalidNearbyValue(String)
    /// Signing failed.
    case signingFailed
}
