// The run-time status of one APNs environment for `lisa doctor`: its fixed endpoint and whether its HTTP transport can
// send HTTP/2-only requests, as reported by the library actually loaded.

import LisaDomain

/// What `lisa doctor` can report about an allowed environment without sending anything.
public struct APNsEnvironmentStatus: Hashable, Sendable {
    public var environment: APNsEnvironment
    /// The fixed endpoint, such as `https://api.push.apple.com:443`.
    public var endpoint: String
    /// The Key ID of this environment's provider tokens.
    public var keyID: String
    /// Whether the transport can send HTTP/2-only requests: HTTP/2 negotiated by TLS ALPN, never HTTP/1.1. When
    /// false, every push to this environment is refused as a capability failure.
    public var http2Only: Bool
    /// The transport's account of itself, such as its library versions.
    public var transportSummary: String
}
