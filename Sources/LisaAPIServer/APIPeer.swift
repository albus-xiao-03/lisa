// What the server tells the request handler about a caller: the listener a request arrived on and whether the peer is
// on this machine. The host turns this into its authentication policy.

import LisaAPIContract

/// The connection a request arrived on.
public struct APIPeer: Hashable, Sendable {
    /// The listener that accepted the connection.
    public var listener: APIListenerRole
    /// Whether the peer has a loopback address on a listener that is not behind a reverse proxy.
    public var isLocal: Bool

    public init(listener: APIListenerRole, isLocal: Bool) {
        self.listener = listener
        self.isLocal = isLocal
    }
}

/// Answers one request. It never throws: every failure is an error response.
public typealias APIRequestHandler = @Sendable (APIRequest, APIPeer) async -> APIResponse

/// A listener the server is serving on.
public struct BoundAPIListener: Hashable, Sendable {
    public var role: APIListenerRole
    public var address: String
    /// The actual port, also when port 0 was configured.
    public var port: Int
    /// `plain`, `reverseProxy` or `tls`.
    public var transport: String
}
