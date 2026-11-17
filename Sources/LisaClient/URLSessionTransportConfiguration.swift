// Settings of URLSessionTransport (timeouts, the response size limit, server trust) and the URLSession they produce.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Settings of a `URLSessionTransport`. Descriptions and reflection show the limits only.
public struct URLSessionTransportConfiguration: Sendable, CustomStringConvertible, CustomReflectable {
    /// The default `requestTimeout`.
    public static let defaultRequestTimeout: Duration = .seconds(30)
    /// The default `resourceTimeout`.
    public static let defaultResourceTimeout: Duration = .seconds(120)
    /// The default `maximumResponseBytes`: 4 MiB.
    public static let defaultMaximumResponseBytes = 4 * 1_048_576
    /// The longest timeout accepted: seven days.
    public static let maximumTimeout: Duration = .seconds(604_800)

    /// How long a request may wait for the connection or for the host's next bytes; reaching it fails the request
    /// with `APITransportError.interrupted`.
    public var requestTimeout: Duration
    /// The longest a whole exchange may take. Only Apple platforms honor it: swift-corelibs-foundation ignores it, so
    /// on Linux only `requestTimeout` bounds a request.
    public var resourceTimeout: Duration
    /// The largest response body accepted, after content decoding; a larger one fails the request with
    /// `APITransportError.interrupted` as soon as it is seen.
    public var maximumResponseBytes: Int
    /// Evaluates the host's TLS certificate, for pinning. Only Apple platforms support it: with
    /// swift-corelibs-foundation the transport refuses to start with one (`URLSessionTransportError`).
    public var serverTrustEvaluator: (any ServerTrustEvaluator)?

    public init(
        requestTimeout: Duration = URLSessionTransportConfiguration.defaultRequestTimeout,
        resourceTimeout: Duration = URLSessionTransportConfiguration.defaultResourceTimeout,
        maximumResponseBytes: Int = URLSessionTransportConfiguration.defaultMaximumResponseBytes,
        serverTrustEvaluator: (any ServerTrustEvaluator)? = nil
    ) {
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes
        self.serverTrustEvaluator = serverTrustEvaluator
    }

    public var description: String {
        "URLSessionTransportConfiguration(requestTimeout: \(requestTimeout), resourceTimeout: \(resourceTimeout), "
            + "maximumResponseBytes: \(maximumResponseBytes), serverTrustEvaluator: \(evaluatorSummary))"
    }

    /// Reflection, as used by `dump` and debuggers, shows the limits and only whether an evaluator is set.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "requestTimeout": requestTimeout, "resourceTimeout": resourceTimeout,
                "maximumResponseBytes": maximumResponseBytes, "serverTrustEvaluator": evaluatorSummary,
            ],
            displayStyle: .struct)
    }

    private var evaluatorSummary: String { serverTrustEvaluator == nil ? "none" : "configured" }

    /// Checks that these settings and `endpoint` can be used on this platform.
    func validate(for endpoint: HostEndpoint) throws(URLSessionTransportError) {
        #if canImport(FoundationNetworking)
            if serverTrustEvaluator != nil { throw .customTrustUnavailable }
            // FoundationNetworking checks that URL.host ("::1") equals libcurl's host ("[::1]"), so it fails every
            // request to an IPv6 literal with URLError.badURL before connecting.
            if endpoint.host.contains(":") { throw .ipv6LiteralUnavailable }
        #endif
        var problems: [String] = []
        for (name, value) in [("requestTimeout", requestTimeout), ("resourceTimeout", resourceTimeout)]
        where value <= .zero || value > Self.maximumTimeout {
            problems.append("\(name) must be positive and at most \(Self.maximumTimeout)")
        }
        if maximumResponseBytes < 1 { problems.append("maximumResponseBytes must be positive") }
        guard problems.isEmpty else { throw .invalidConfiguration(problems.joined(separator: "; ")) }
    }

    /// An ephemeral session configuration with no cookies, no credential storage, no cache and these timeouts.
    func makeSessionConfiguration() -> URLSessionConfiguration {
        let session = URLSessionConfiguration.ephemeral
        session.httpCookieStorage = nil
        session.httpCookieAcceptPolicy = .never
        session.httpShouldSetCookies = false
        session.urlCredentialStorage = nil
        session.urlCache = nil
        session.requestCachePolicy = .reloadIgnoringLocalCacheData
        session.timeoutIntervalForRequest = requestTimeoutInterval
        session.timeoutIntervalForResource = Self.seconds(resourceTimeout)
        return session
    }

    /// `requestTimeout` in seconds.
    var requestTimeoutInterval: TimeInterval { Self.seconds(requestTimeout) }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
