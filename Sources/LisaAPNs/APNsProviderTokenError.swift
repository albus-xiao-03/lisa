// Why a provider token could not be created; messages name the secret reference at most, never key material.

/// A provider-token failure. Nothing is sent when a token cannot be made.
public enum APNsProviderTokenError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The secret store could not provide the key; the text names the reference only.
    case signingKeyUnavailable(String)
    /// The secret is not a PEM-encoded P-256 private key, the form of an APNs `.p8` key.
    case invalidSigningKey
    /// The Team ID or Key ID is not a 10-character identifier.
    case invalidIdentifiers
    /// Signing failed.
    case signingFailed

    public var description: String {
        switch self {
        case .signingKeyUnavailable(let reason): "the APNs signing key is unavailable: \(reason)"
        case .invalidSigningKey: "the APNs signing key is not a PEM-encoded P-256 private key (.p8)"
        case .invalidIdentifiers: "the APNs Team ID or Key ID is not a 10-character identifier"
        case .signingFailed: "the APNs provider token could not be signed"
        }
    }
}
