// The server-trust evaluator for a Lisa host with owner-supplied trust: SecTrust anchored only to the owner's
// certificate or certificate authority, with the host name checked, and an optional pin of the host's certificate.

import CryptoKit
import Foundation
import LisaClient
import LisaPresentation
import Security

/// Decides URLSession's server-trust challenges for one Lisa host whose certificate the owner supplied (API-01, D-45).
///
/// A challenge is accepted only when all of these hold; any doubt refuses it, and there is no way to allow an
/// untrusted certificate:
/// - it is a server-trust challenge for this evaluator's host;
/// - the certificate chain evaluates (`SecTrustEvaluateWithError`) under an SSL server policy for the host name,
///   anchored only to the owner's certificates (`SecTrustSetAnchorCertificates` with
///   `SecTrustSetAnchorCertificatesOnly`), without fetching anything from the network;
/// - with a pin, the host's own certificate has exactly the pinned SHA-256 digest.
///
/// The system's own rules for TLS server certificates still apply, such as a subject alternative name matching the
/// host and, for certificates from the owner's own authority, a validity of at most 825 days.
struct PinnedServerTrustEvaluator: ServerTrustEvaluator {
    /// The host name or IP address the certificate must be valid for, in lowercase, without brackets.
    let host: String
    private let anchorCertificates: [Data]
    private let leafCertificateSHA256: Data?

    /// An evaluator for `endpoint` that trusts only `trust`.
    ///
    /// - Throws: `HostTrustSettingsError.unreadableCertificate` when a certificate is not a DER certificate the
    ///   Security framework can read.
    init(trust: HostTrustSettings, endpoint: HostEndpoint) throws(HostTrustSettingsError) {
        guard trust.anchorCertificates.allSatisfy({ SecCertificateCreateWithData(nil, $0 as CFData) != nil }) else {
            throw .unreadableCertificate
        }
        host = Self.normalized(endpoint.host)
        anchorCertificates = trust.anchorCertificates
        leafCertificateSHA256 = trust.leafCertificateSHA256
    }

    func credential(forServerTrustOf protectionSpace: URLProtectionSpace) -> URLCredential? {
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            Self.normalized(protectionSpace.host) == host, let trust = protectionSpace.serverTrust
        else { return nil }
        let anchors = anchorCertificates.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard anchors.count == anchorCertificates.count else { return nil }
        let policy = SecPolicyCreateSSL(true, host as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess,
            SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
            SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
        else { return nil }
        guard SecTrustEvaluateWithError(trust, nil) else { return nil }
        if let pin = leafCertificateSHA256 {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
                return nil
            }
            let digest = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
            guard digest == pin else { return nil }
        }
        return URLCredential(trust: trust)
    }

    /// `host` in lowercase, without IPv6 brackets or a trailing dot.
    private static func normalized(_ host: String) -> String {
        var text = host.lowercased()
        if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()) }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
