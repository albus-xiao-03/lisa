// The HTTP client boundary every network adapter uses: requests, responses, failures that say whether the request
// may have been sent, and the HTTPClient protocol (implemented with libcurl by LisaCurl).

import Foundation

/// One header field. Names compare case-insensitively. A sensitive value never appears in a description or mirror.
public struct HTTPHeader: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var name: String
    public var value: String
    /// A credential (such as `Authorization`): never logged, and dropped when a redirect leaves the origin.
    public var isSensitive: Bool

    public init(_ name: String, _ value: String, sensitive: Bool = false) {
        self.name = name
        self.value = value
        self.isSensitive = sensitive || name.lowercased() == "authorization"
    }

    /// Whether the name and value are free of CR, LF and NUL, and the name is a valid field-name token. libcurl sends
    /// header strings verbatim, so anything else could inject headers.
    public var isWellFormed: Bool {
        let tokenCharacters = Set("!#$%&'*+-.^_`|~".utf8)
        let nameValid =
            !name.isEmpty
            && name.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                    || tokenCharacters.contains(byte)
            }
        return nameValid && !value.utf8.contains { $0 == 0x0D || $0 == 0x0A || $0 == 0x00 }
    }

    public var description: String { isSensitive ? "\(name): <redacted>" : "\(name): \(value)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["field": description]) }
}

/// Which HTTP version a request needs.
public enum HTTPVersionRequirement: Hashable, Sendable {
    /// HTTP/2 when the server offers it, otherwise HTTP/1.1.
    case any
    /// HTTP/2 only (APNs, NOTIFY-04): only `h2` is offered in TLS ALPN and the request is never sent over HTTP/1.1.
    /// libcurl still speaks HTTP/2 to a TLS server that selects no ALPN protocol at all; such an exchange fails and
    /// is reported as possibly sent.
    case http2Only
}

/// Whether redirects are followed. Every hop is re-checked against the URL and address policy.
public enum RedirectPolicy: Hashable, Sendable {
    case none
    case follow(max: Int)
}

/// Which remote addresses a request may connect to (SEC-02). Every policy is checked against each resolved address
/// when the connection is opened, and again before request bytes are sent on a reused connection.
public enum AddressPolicy: Hashable, Sendable {
    /// Public internet addresses only: no loopback, private, shared, link-local (cloud metadata), multicast or
    /// reserved addresses.
    case publicOnly
    /// Also loopback and private networks, for an endpoint the owner configured with such an address (a local model
    /// server, or a mail server named by a private address).
    case allowLocalNetworks
    /// Loopback only: the one case where plain `http` is allowed, for a model server on the same machine.
    case loopbackOnly
}

/// One HTTP request. Its description and mirror show only the method, the origin and the header names, because
/// paths, queries, bodies and credentials can be private.
public struct HTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var method: String
    public var url: URL
    public var headers: [HTTPHeader]
    public var body: Data?
    /// The whole exchange, including connection setup.
    public var timeoutSeconds: Double
    /// Connection setup (DNS, TCP, TLS).
    public var connectTimeoutSeconds: Double
    /// The response body is aborted beyond this size.
    public var maxResponseBytes: Int
    /// The response header block is aborted beyond this size.
    public var maxHeaderBytes: Int
    public var version: HTTPVersionRequirement
    public var redirects: RedirectPolicy
    public var addresses: AddressPolicy

    public init(
        method: String = "GET", url: URL, headers: [HTTPHeader] = [], body: Data? = nil, timeoutSeconds: Double = 30,
        connectTimeoutSeconds: Double = 10, maxResponseBytes: Int = 10_000_000, maxHeaderBytes: Int = 65_536,
        version: HTTPVersionRequirement = .any, redirects: RedirectPolicy = .none,
        addresses: AddressPolicy = .publicOnly
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutSeconds = timeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.maxResponseBytes = maxResponseBytes
        self.maxHeaderBytes = maxHeaderBytes
        self.version = version
        self.redirects = redirects
        self.addresses = addresses
    }

    /// The method and origin only, safe to log: paths and queries can carry secrets (private calendar addresses).
    public var logLabel: String { "\(method) \(URLPolicy.origin(of: url))" }

    public var description: String {
        "\(logLabel) headers: [\(headers.map(\.name).joined(separator: ", "))] body: \(body?.count ?? 0) bytes"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["request": description]) }

    /// The first value of a header, ignoring the case of its name.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.name.lowercased() == lowered }?.value
    }
}

/// The HTTP version a response actually used.
public enum HTTPVersion: String, Hashable, Sendable {
    case http10 = "HTTP/1.0"
    case http11 = "HTTP/1.1"
    case http2 = "HTTP/2"
    case http3 = "HTTP/3"
}

/// One HTTP response.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [HTTPHeader]
    public var body: Data
    /// The version actually used, as reported by the transport after the exchange.
    public var version: HTTPVersion
    /// The address actually connected to, for diagnostics.
    public var remoteAddress: String?
    /// Redirects followed to reach this response.
    public var redirectCount: Int
    /// The URL that produced this response, after any redirects.
    public var finalURL: URL

    public init(
        status: Int, headers: [HTTPHeader], body: Data, version: HTTPVersion, remoteAddress: String? = nil,
        finalURL: URL, redirectCount: Int = 0
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.version = version
        self.remoteAddress = remoteAddress
        self.finalURL = finalURL
        self.redirectCount = redirectCount
    }

    public var isSuccess: Bool { (200...299).contains(status) }

    /// The first value of a header, ignoring the case of its name.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.name.lowercased() == lowered }?.value
    }
}

/// Why an exchange failed. Each case states whether request bytes may have reached the server, which decides
/// whether a delivery may be retried or must be recorded as an uncertain outcome (plan §6.4).
public enum HTTPFailure: Error, Hashable, Sendable, CustomStringConvertible {
    /// Refused by policy before anything was sent: scheme, credentials in the URL, malformed headers, or no allowed
    /// address to connect to.
    case refused(String)
    /// The transport cannot perform this kind of request in this environment (for example, HTTP/2 only).
    case unsupported(String)
    /// The exchange was cancelled by the caller.
    case cancelled(requestSent: Bool)
    /// Name resolution, connection or TLS setup failed; nothing was sent.
    case notSent(String)
    /// The server's certificate or name did not verify; nothing was sent.
    case untrustedServer(String)
    /// HTTP/2 was required but not negotiated; nothing was sent.
    case http2Unavailable
    /// The exchange exceeded its time limit.
    case timedOut(requestSent: Bool)
    /// The connection failed during the exchange.
    case connectionLost(requestSent: Bool, String)
    /// The response body exceeded the request's limit; the exchange was aborted.
    case responseTooLarge(limit: Int)
    /// A redirect led somewhere the policy does not allow, or there were too many.
    case redirectRefused(String)
    /// The server's reply was not valid HTTP.
    case protocolError(String)

    /// Whether request bytes may have reached the server.
    public var requestMayHaveBeenSent: Bool {
        switch self {
        case .refused, .unsupported, .notSent, .untrustedServer, .http2Unavailable: false
        case .timedOut(let sent), .connectionLost(let sent, _), .cancelled(let sent): sent
        case .responseTooLarge, .redirectRefused, .protocolError: true
        }
    }

    public var description: String {
        switch self {
        case .refused(let reason): "the request was refused by policy: \(reason)"
        case .unsupported(let reason): "the transport cannot perform this request: \(reason)"
        case .cancelled(let sent): "the request was cancelled " + (sent ? "after it was sent" : "before it was sent")
        case .notSent(let reason): "the request was not sent: \(reason)"
        case .untrustedServer(let reason): "the server's certificate could not be verified: \(reason)"
        case .http2Unavailable: "the server did not negotiate HTTP/2, which this request requires"
        case .timedOut(let sent): "the request timed out " + (sent ? "after it was sent" : "before it was sent")
        case .connectionLost(let sent, let reason):
            "the connection was lost " + (sent ? "after the request was sent" : "before the request was sent")
                + ": \(reason)"
        case .responseTooLarge(let limit): "the response exceeded \(limit) bytes"
        case .redirectRefused(let reason): "a redirect was refused: \(reason)"
        case .protocolError(let reason): "the server's reply was not valid HTTP: \(reason)"
        }
    }
}

/// What a client's transport can do, determined at run time from the library actually loaded.
public struct HTTPClientCapabilities: Hashable, Sendable {
    /// Whether `.http2Only` requests can be sent: HTTP/2 negotiated by TLS ALPN, with no HTTP/1.1 fallback.
    public var http2Only: Bool
    /// A human-readable account of the transport, such as its library versions, for `lisa doctor`.
    public var summary: String

    public init(http2Only: Bool, summary: String) {
        self.http2Only = http2Only
        self.summary = summary
    }
}

/// Performs HTTP exchanges. Implementations enforce TLS certificate validation, the URL and address policy at
/// connect time, the size and time limits, and the version requirement; they never fall back to weaker settings.
public protocol HTTPClient: Sendable {
    var capabilities: HTTPClientCapabilities { get }
    func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse
}
