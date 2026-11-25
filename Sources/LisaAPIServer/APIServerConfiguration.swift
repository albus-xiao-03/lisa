// The network server's settings: its listeners (role, address, port, transport) and the limits every connection obeys.

import LisaAPIContract

/// Who a listener serves.
public enum APIListenerRole: String, Hashable, Sendable {
    /// Paired devices and pairing (API-01). Only device credentials are accepted.
    case devices
    /// The host's own command-line clients on this machine: loopback peers presenting the owner credential.
    case owner
}

/// How a listener is protected in transit (API-01).
public enum APIListenerTransport: Sendable {
    /// Plain HTTP; only on a loopback address.
    case plain
    /// Plain HTTP for a trusted reverse proxy that terminates TLS. Every request arrives from the proxy, so no peer
    /// counts as local, even when the proxy connects over loopback.
    case reverseProxy
    /// TLS served by Lisa.
    case tls(APIServerTLS)

    /// A short name for logs and errors.
    public var name: String {
        switch self {
        case .plain: "plain"
        case .reverseProxy: "reverseProxy"
        case .tls: "tls"
        }
    }
}

/// One address the server listens on.
public struct APIListenerConfiguration: Sendable {
    public var role: APIListenerRole
    /// An IPv4 or IPv6 literal; host names are never resolved.
    public var address: String
    /// The TCP port; 0 picks a free one.
    public var port: Int
    public var transport: APIListenerTransport

    public init(role: APIListenerRole, address: String, port: Int, transport: APIListenerTransport) {
        self.role = role
        self.address = address
        self.port = port
        self.transport = transport
    }

    /// Whether requests on this listener can come straight from a peer on this machine.
    var peersMayBeLocal: Bool {
        if case .reverseProxy = transport { return false }
        return true
    }
}

/// Limits for every connection. Defaults suit a personal host: a few clients, small JSON requests.
public struct APIServerLimits: Hashable, Sendable {
    /// The request line and all header fields together.
    public var maxHeaderBytes: Int
    public var maxHeaderFields: Int
    /// The request body; larger requests get 413.
    public var maxBodyBytes: Int
    /// After a rejection, at most this many further body bytes are read and discarded so the client can still read
    /// the response; beyond that the connection is closed at once.
    public var maxDiscardBytes: Int
    /// From the start of a connection, including any TLS handshake, to its first complete request head.
    public var firstRequestTimeout: Duration
    /// From the end of a response to the next complete request head on a kept-alive connection.
    public var keepAliveTimeout: Duration
    /// From a request head to the end of its body.
    public var bodyTimeout: Duration
    /// Connections served at once; further connections are closed immediately.
    public var maxConnections: Int
    /// How long shutdown waits for requests in progress before closing their connections.
    public var shutdownGracePeriod: Duration
    /// Larger body limits for exact request paths (R2's `POST /v2/operations`, plan §8.12.1); every other path keeps
    /// `maxBodyBytes`, with the same 413 and close.
    public var bodyLimitsByPath: [String: Int]

    public init(
        maxHeaderBytes: Int = 16_384, maxHeaderFields: Int = 100, maxBodyBytes: Int = APIVersioning.maxRequestBytes,
        maxDiscardBytes: Int = 1_048_576, firstRequestTimeout: Duration = .seconds(20),
        keepAliveTimeout: Duration = .seconds(30), bodyTimeout: Duration = .seconds(30), maxConnections: Int = 64,
        shutdownGracePeriod: Duration = .seconds(5), bodyLimitsByPath: [String: Int] = [:]
    ) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxHeaderFields = maxHeaderFields
        self.maxBodyBytes = maxBodyBytes
        self.maxDiscardBytes = maxDiscardBytes
        self.firstRequestTimeout = firstRequestTimeout
        self.keepAliveTimeout = keepAliveTimeout
        self.bodyTimeout = bodyTimeout
        self.maxConnections = maxConnections
        self.shutdownGracePeriod = shutdownGracePeriod
        self.bodyLimitsByPath = bodyLimitsByPath
    }

    /// The problems that make these limits unusable, if any.
    var problems: [String] {
        var problems: [String] = []
        if maxHeaderBytes < 1024 { problems.append("maxHeaderBytes must be at least 1024") }
        if maxHeaderFields < 8 { problems.append("maxHeaderFields must be at least 8") }
        if maxBodyBytes < 0 { problems.append("maxBodyBytes must not be negative") }
        if bodyLimitsByPath.values.contains(where: { $0 < 0 }) {
            problems.append("a path's body limit must not be negative")
        }
        if maxDiscardBytes < 0 { problems.append("maxDiscardBytes must not be negative") }
        if maxConnections < 1 { problems.append("maxConnections must be at least 1") }
        for (name, value) in [
            ("firstRequestTimeout", firstRequestTimeout), ("keepAliveTimeout", keepAliveTimeout),
            ("bodyTimeout", bodyTimeout),
        ] where value <= .zero {
            problems.append("\(name) must be positive")
        }
        if shutdownGracePeriod < .zero { problems.append("shutdownGracePeriod must not be negative") }
        return problems
    }
}
