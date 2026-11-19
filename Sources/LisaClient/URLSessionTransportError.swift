// Why a URLSessionTransport cannot be created on this platform or with these settings.

/// Why a `URLSessionTransport` cannot be created.
public enum URLSessionTransportError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A server trust evaluator is configured, but this platform's URLSession (swift-corelibs-foundation) raises no
    /// server-trust challenges, so the evaluator would never run and system trust would apply instead.
    case customTrustUnavailable
    /// The endpoint's host is an IPv6 literal, such as `[::1]`, which this platform's URLSession
    /// (swift-corelibs-foundation) rejects in every request URL.
    case ipv6LiteralUnavailable
    /// A timeout or limit is out of range.
    case invalidConfiguration(String)

    public var description: String {
        switch self {
        case .customTrustUnavailable:
            "custom TLS trust is not available with swift-corelibs-foundation URLSession: a server trust evaluator "
                + "(certificate or CA pinning) cannot be used on this platform"
        case .ipv6LiteralUnavailable:
            "IPv6 address literals such as [::1] are not usable with swift-corelibs-foundation URLSession, which "
                + "rejects every such URL; use a host name such as localhost, or an IPv4 address"
        case .invalidConfiguration(let reason): "the URLSession transport settings are invalid: \(reason)"
        }
    }
}
