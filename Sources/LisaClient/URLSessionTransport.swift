// The URLSession transport to a Lisa host: HTTPS (or HTTP on loopback) with no cookies, credential storage, cache or
// redirects, request checks before sending, and failures mapped to APITransportError.

import Foundation
import LisaAPIContract
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Carries API requests to a Lisa host with URLSession (API-01): over HTTPS, or plain HTTP to a loopback host.
///
/// - One ephemeral session per transport, with no cookie storage, credential storage or URL cache; every request
///   reloads from the host.
/// - Redirects are never followed: a 3xx response is returned like any other response.
/// - Authentication challenges are never answered with a credential, so a 401 such as one with
///   `WWW-Authenticate: Bearer realm="lisa"` comes back as a response. The only exception is a server-trust challenge
///   on an Apple platform, which the configured `ServerTrustEvaluator` decides.
/// - A response body larger than `configuration.maximumResponseBytes` fails with `APITransportError.interrupted`.
/// - Requests are checked before sending: the path must start with `/v1/`, header names must be HTTP tokens, values
///   printable ASCII, framing headers (such as `Host` or `Content-Length`) are left to URLSession, and a GET carries no
///   body. A rejected request fails with `APITransportError.refused`.
/// - Failures map to `APITransportError` (see `TransportFailureMapping`); cancelling the calling task throws
///   `CancellationError`. Descriptions and reflection never show headers, bodies or credentials.
///
/// With swift-corelibs-foundation (Linux), a server trust evaluator and an IPv6 literal host are refused when the
/// transport is created, `resourceTimeout` is ignored, and libcurl sends requests through the proxy named by the
/// `http_proxy`, `all_proxy` or `ALL_PROXY` environment variable, loopback hosts included, unless `no_proxy` or
/// `NO_PROXY` lists the host.
///
/// The session keeps a strong reference to its delegate until it is invalidated: call `invalidate()` when done. A
/// transport that is deinitialized invalidates its session as well.
public final class URLSessionTransport: APITransport, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// Header names that URLSession and libcurl manage; a request that sets one is refused.
    static let managedHeaderNames: Set<String> = [
        "connection", "content-length", "expect", "host", "keep-alive", "proxy-authorization", "proxy-connection", "te",
        "trailer", "transfer-encoding", "upgrade",
    ]

    /// The host's base address.
    public let endpoint: HostEndpoint
    public let configuration: URLSessionTransportConfiguration
    private let session: URLSession
    private let delegate: TransportSessionDelegate
    private let isInvalidated = Mutex(false)

    /// A transport to `endpoint`.
    ///
    /// - Throws: `URLSessionTransportError`: `.customTrustUnavailable` when `configuration` has a server trust
    ///   evaluator, or `.ipv6LiteralUnavailable` when the endpoint's host is an IPv6 literal, and this platform's
    ///   URLSession (swift-corelibs-foundation) cannot handle it; `.invalidConfiguration` for a timeout or limit out of
    ///   range.
    public init(
        endpoint: HostEndpoint, configuration: URLSessionTransportConfiguration = URLSessionTransportConfiguration()
    ) throws(URLSessionTransportError) {
        try configuration.validate(for: endpoint)
        self.endpoint = endpoint
        self.configuration = configuration
        delegate = TransportSessionDelegate(
            maximumResponseBytes: configuration.maximumResponseBytes,
            serverTrustEvaluator: configuration.serverTrustEvaluator)
        session = URLSession(
            configuration: configuration.makeSessionConfiguration(), delegate: delegate, delegateQueue: nil)
    }

    deinit {
        invalidate()
    }

    /// Sends `request` and returns the host's response, whatever its status.
    ///
    /// - Throws: `APITransportError`, or `CancellationError` when the calling task is cancelled before a response
    ///   arrives (the request may have been delivered).
    public func send(_ request: APIRequest) async throws -> APIResponse {
        let urlRequest = try makeURLRequest(for: request)
        try Task.checkCancellation()
        let task = try makeTask(for: urlRequest)
        switch await delegate.run(task) {
        case .response(let response): return response
        case .failure(let error): throw error
        case .cancelled: throw CancellationError()
        }
    }

    /// Stops accepting requests and invalidates the session once the requests in flight finish, releasing its
    /// delegate. Later requests fail with `APITransportError.refused`.
    public func invalidate() {
        let invalidatesNow = isInvalidated.withLock { invalidated in
            defer { invalidated = true }
            return !invalidated
        }
        if invalidatesNow { session.finishTasksAndInvalidate() }
    }

    public var description: String { "URLSessionTransport(\(endpoint))" }

    public var debugDescription: String { description }

    /// Reflection, as used by `dump` and debuggers, shows the endpoint and the limits only.
    public var customMirror: Mirror {
        Mirror(
            self, children: ["endpoint": endpoint.description, "configuration": configuration.description],
            displayStyle: .class)
    }

    // MARK: - Requests

    /// The URLRequest for `request`, or a refusal when it cannot be sent safely. Refusal reasons may name a header,
    /// never its value.
    func makeURLRequest(for request: APIRequest) throws(APITransportError) -> URLRequest {
        let url = try endpoint.url(for: request)
        guard request.method != .get || request.body == nil else { throw .refused("a GET request cannot have a body") }
        try Self.checkHeaders(request.headers)
        var urlRequest = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.requestTimeoutInterval)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    /// A data task for `request`, unless the transport was invalidated: a task created on an invalidated session
    /// would end the process.
    private func makeTask(for request: URLRequest) throws(APITransportError) -> URLSessionDataTask {
        let task = isInvalidated.withLock { invalidated -> URLSessionDataTask? in
            invalidated ? nil : session.dataTask(with: request)
        }
        guard let task else { throw .refused("the transport has been invalidated") }
        return task
    }

    /// Refuses header names that are not HTTP tokens, names URLSession manages, names repeated in another case, and
    /// values that are empty, padded with spaces, or not printable ASCII (a CR or LF would inject header lines).
    private static func checkHeaders(_ headers: [String: String]) throws(APITransportError) {
        var seen: Set<String> = []
        for (name, value) in headers {
            guard isToken(name) else { throw .refused("a request header name is not a valid HTTP field name") }
            let lowercased = name.lowercased()
            guard !managedHeaderNames.contains(lowercased) else {
                throw .refused("the request sets the \(name) header, which the transport manages")
            }
            guard seen.insert(lowercased).inserted else { throw .refused("the request sets the \(name) header twice") }
            guard isFieldValue(value) else {
                throw .refused("the \(name) header value is empty, padded or not printable ASCII")
            }
        }
    }

    /// Whether `name` is an RFC 9110 token.
    private static func isToken(_ name: String) -> Bool {
        let symbols = Set("!#$%&'*+-.^_`|~".utf8)
        return !name.isEmpty
            && name.utf8.allSatisfy { byte in
                (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                    || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                    || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) || symbols.contains(byte)
            }
    }

    /// Whether `value` is a non-empty field value of visible ASCII with inner spaces or tabs only.
    private static func isFieldValue(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let first = bytes.first, let last = bytes.last else { return false }
        let isVisible = { (byte: UInt8) in (0x21...0x7E).contains(byte) }
        return isVisible(first) && isVisible(last) && bytes.allSatisfy { isVisible($0) || $0 == 0x20 || $0 == 0x09 }
    }
}
