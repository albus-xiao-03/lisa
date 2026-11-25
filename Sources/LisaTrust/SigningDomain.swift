// Signing domains: every Lisa signature covers a domain prefix followed by the exact body (plan §8.16.1).

/// The ASCII prefix that separates one kind of signed message from every other. A signature is always over
/// `prefix ‖ body`, and the body is never re-encoded.
public struct SigningDomain: Hashable, Sendable {
    /// The prefix bytes, ending in a newline.
    public let prefix: [UInt8]

    /// - Precondition: `text` is printable ASCII ending in one newline.
    public init(_ text: String) {
        let bytes = Array(text.utf8)
        precondition(
            bytes.last == 0x0A && bytes.dropLast().allSatisfy { (0x21...0x7E).contains($0) },
            "a signing domain is printable ASCII ending in a newline")
        prefix = bytes
    }

    /// The message a signature covers: the prefix, then the body.
    public func message(for body: [UInt8]) -> [UInt8] { prefix + body }

    /// Device operations (plan §8.2.1).
    public static let operation = SigningDomain("lisa-r2-op\n")
    /// Core's signed enrollment result (plan §8.1.2 step 5.7).
    public static let enrollmentResult = SigningDomain("lisa-r2-enroll-result-v1\n")
    /// Core's token-free TLS anchors bundle (plan §8.1.2 step 3).
    public static let tlsAnchors = SigningDomain("lisa-r2-tls-anchors-v1\n")
    /// A device's enrollment request (plan §8.1.2 step 4).
    public static let enrollmentRequest = SigningDomain("lisa-r2-enroll-request-v1\n")
    /// Nearby session authentication (plan §8.7).
    public static let nearbyAuthentication = SigningDomain("lisa-nearby-auth-v1\n")
    /// The header of a paged artifact: rosters with key history, causal summaries, snapshot manifests (plan §8.1.3).
    public static let pagedArtifactHeader = SigningDomain("lisa-r2-paged-artifact-v1\n")
    /// A protected archive, signed by its exporting device over the header and ciphertext digests (plan §8.6.6).
    public static let archive = SigningDomain("lisa-r2-archive-v1\n")
    /// A change page, signed by Core over its canonical body (plan §8.4.2).
    public static let changePage = SigningDomain("lisa-r2-change-page-v1\n")
    /// A peer's custody acknowledgement, signed by the holder over its canonical body (plan §8.6.1, §8.7).
    public static let custodyAcknowledgement = SigningDomain("lisa-r2-custody-v1\n")
    /// Core's receipt for one operation, over its canonical body (plan §8.2.1).
    public static let receipt = SigningDomain("lisa-r2-receipt-v1\n")
    /// Core's authorization record for one device, returned at enrollment with the roster (plan §8.1.2 step 5.7).
    public static let deviceAuthorization = SigningDomain("lisa-r2-device-authorization-v1\n")
    /// A device's credential-reset request, signed by its existing operation key (plan §8.1.4).
    public static let credentialReset = SigningDomain("lisa-r2-credential-reset-v1\n")
}
