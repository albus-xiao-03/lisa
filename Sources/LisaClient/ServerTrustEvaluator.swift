// The seam for pinning a Lisa host's TLS certificate: a ServerTrustEvaluator decides URLSession server-trust challenges.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Decides whether to trust a Lisa host's TLS certificate, for example by pinning the host's public key or its
/// certificate authority, instead of relying on the system's trust settings alone.
///
/// Only Apple platforms raise server-trust challenges; an Apple-only adapter evaluates `protectionSpace.serverTrust`
/// with the Security framework. App Transport Security still applies there. swift-corelibs-foundation's URLSession
/// (Linux, Windows) never raises one and always uses the system's trust store, so `URLSessionTransport` refuses to
/// start with an evaluator there (`URLSessionTransportError.customTrustUnavailable`) rather than silently skipping
/// the evaluation.
public protocol ServerTrustEvaluator: Sendable {
    /// Evaluates the server trust of `protectionSpace`, whose authentication method is
    /// `NSURLAuthenticationMethodServerTrust`, and returns the credential that accepts it (normally
    /// `URLCredential(trust:)` for the evaluated trust), or `nil` to refuse the connection. A refusal fails the
    /// request with `APITransportError.refused` before anything is sent.
    func credential(forServerTrustOf protectionSpace: URLProtectionSpace) -> URLCredential?
}
