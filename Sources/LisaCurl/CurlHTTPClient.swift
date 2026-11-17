// The libcurl implementation of LisaHTTP's HTTPClient: TLS 1.2 or later with peer and host verification, no proxy,
// connect-time address checks, body and header size limits, time limits, cancellation, re-validated redirects, and a
// strict HTTP/2-only mode verified after each exchange.

import CCurl
import CCurlShim
import Foundation
import LisaHTTP

/// Sends HTTP requests with libcurl.
public final class CurlHTTPClient: HTTPClient {
    public struct Configuration: Sendable {
        /// A PEM bundle that replaces the system trust store; verification stays on. Lisa's host never sets it; it
        /// exists for loopback verification against a synthetic certificate authority.
        public var trustStorePath: String?
        /// The `User-Agent` sent when a request does not set one.
        public var userAgent: String
        /// How many idle handles, and so connections, are kept for reuse.
        public var idleHandles: Int
        /// How long an idle connection may be reused, in seconds (libcurl's default is 118).
        public var maxIdleConnectionSeconds: Int

        public init(
            trustStorePath: String? = nil, userAgent: String = "Lisa", idleHandles: Int = 4,
            maxIdleConnectionSeconds: Int = 118
        ) {
            self.trustStorePath = trustStorePath
            self.userAgent = userAgent
            self.idleHandles = idleHandles
            self.maxIdleConnectionSeconds = maxIdleConnectionSeconds
        }
    }

    public let configuration: Configuration
    public let library: CurlLibraryInfo
    private let pool: CurlHandlePool

    public init(configuration: Configuration = Configuration()) throws(CurlSetupError) {
        self.configuration = configuration
        library = try CurlRuntime.library()
        pool = CurlHandlePool(capacity: configuration.idleHandles)
    }

    public var capabilities: HTTPClientCapabilities {
        HTTPClientCapabilities(http2Only: library.supportsHTTP2Only, summary: library.summary)
    }

    public func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        try await HTTPRedirects.send(request) { (hop: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse in
            try await self.exchange(hop)
        }
    }

    /// One exchange, without following redirects.
    func exchange(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        guard request.headers.allSatisfy(\.isWellFormed) else {
            throw .refused("a header name or value contains characters that are not allowed")
        }
        guard request.method.utf8.allSatisfy({ (0x41...0x5A).contains($0) }), !request.method.isEmpty else {
            throw .refused("the method is not a valid HTTP method")
        }
        if request.version == .http2Only, !library.supportsHTTP2Only {
            throw .unsupported("\(library.summary); HTTP/2-only requests need libcurl 8.10.0 or later with HTTP/2")
        }
        let cancellation = CurlCancellation()
        let pool = self.pool
        let configuration = self.configuration
        let cancel: @Sendable () -> Void = { cancellation.cancel() }
        let result = await CurlWorkerThread.run(name: "lisa.curl.http", onCancel: cancel) {
            CurlHTTPExchange(request: request, configuration: configuration, cancellation: cancellation, pool: pool)
                .perform()
        }
        return try result.get()
    }
}

/// One blocking exchange on the current thread.
struct CurlHTTPExchange {
    let request: HTTPRequest
    let configuration: CurlHTTPClient.Configuration
    let cancellation: CurlCancellation
    let pool: CurlHandlePool

    func perform() -> Result<HTTPResponse, HTTPFailure> {
        if cancellation.isCancelled { return .failure(.cancelled(requestSent: false)) }
        let easy: CurlEasy
        do { easy = try pool.take() } catch { return .failure(.unsupported(error.description)) }
        let transfer = CurlTransfer(maxBodyBytes: request.maxResponseBytes, maxHeaderBytes: request.maxHeaderBytes)
        let gate = CurlAddressGate(policy: request.addresses)
        let headerList: CurlStringList
        do {
            headerList = try configure(easy, transfer: transfer, gate: gate)
        } catch {
            return .failure(.refused("the request could not be prepared: \(error.description)"))
        }
        let code = withExtendedLifetime(headerList) { curl_easy_perform(easy.handle) }
        let requestSent = gate.requestStarted || transfer.receivedResponse
        guard code == CURLE_OK else {
            let message = String(cString: curl_easy_strerror(code))
            let failure = CurlFailureMapping.failure(
                code, message: message, requestSent: requestSent, transfer: transfer, gate: gate,
                cancelled: cancellation.isCancelled, http2Only: request.version == .http2Only)
            pool.give(back: easy, reusable: false)
            return .failure(failure)
        }
        let status = easy.long(CURLINFO_RESPONSE_CODE) ?? 0
        let version = Self.version(easy.long(CURLINFO_HTTP_VERSION) ?? 0)
        let remote = easy.string(CURLINFO_PRIMARY_IP)
        pool.give(back: easy, reusable: true)
        guard (100...599).contains(status), let version else {
            return .failure(.protocolError("the server did not send a valid HTTP status"))
        }
        if request.version == .http2Only, version != .http2 {
            // CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE allows only HTTP/2, so this should not happen; it is checked
            // rather than assumed (NOTIFY-04).
            return .failure(.protocolError("the response used \(version.rawValue), but this request requires HTTP/2"))
        }
        return .success(
            HTTPResponse(
                status: status, headers: transfer.headers, body: transfer.body, version: version, remoteAddress: remote,
                finalURL: request.url))
    }

    /// Sets every option for this exchange; returns the header list, which must outlive the transfer.
    private func configure(_ easy: CurlEasy, transfer: CurlTransfer, gate: CurlAddressGate) throws(CurlOptionError)
        -> CurlStringList
    {
        let plainHTTP = request.url.scheme?.lowercased() == "http"
        try easy.set(CURLOPT_URL, request.url.absoluteString)
        try easy.set(CURLOPT_PROTOCOLS_STR, plainHTTP ? "http" : "https")
        try easy.set(CURLOPT_REDIR_PROTOCOLS_STR, plainHTTP ? "http" : "https")
        try easy.set(CURLOPT_FOLLOWLOCATION, 0)
        // Environment proxies are ignored: with a proxy, the address Lisa checks would be the proxy's, not the
        // destination's (SEC-02).
        try easy.set(CURLOPT_PROXY, "")
        try easy.set(CURLOPT_NOSIGNAL, 1)
        try easy.set(CURLOPT_SSLVERSION, Int(CURL_SSLVERSION_TLSv1_2))
        try easy.set(CURLOPT_SSL_VERIFYPEER, 1)
        try easy.set(CURLOPT_SSL_VERIFYHOST, 2)
        if let trustStore = configuration.trustStorePath { try easy.set(CURLOPT_CAINFO, trustStore) }
        try easy.set(
            CURLOPT_HTTP_VERSION,
            request.version == .http2Only ? Int(CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE) : Int(CURL_HTTP_VERSION_2TLS))
        try easy.set(CURLOPT_TIMEOUT_MS, Self.milliseconds(request.timeoutSeconds))
        try easy.set(
            CURLOPT_CONNECTTIMEOUT_MS, Self.milliseconds(min(request.connectTimeoutSeconds, request.timeoutSeconds)))
        try easy.set(CURLOPT_MAXAGE_CONN, max(1, configuration.maxIdleConnectionSeconds))
        try easy.set(CURLOPT_MAXFILESIZE_LARGE, offset: Int64(max(1, request.maxResponseBytes)))
        try check(lisa_curl_install_address_gate(easy.handle, gate.cGate))
        try check(lisa_curl_set_abort_check(easy.handle, cancellation.binding))
        try check(lisa_curl_set_write_callback(easy.handle, curlWriteBody, transfer.userdata))
        try check(lisa_curl_set_header_callback(easy.handle, curlWriteHeader, transfer.userdata))

        let method = request.method
        switch method {
        case "GET":
            try easy.set(CURLOPT_HTTPGET, 1)
        case "HEAD":
            try easy.set(CURLOPT_NOBODY, 1)
        default:
            let body = request.body ?? Data()
            try easy.set(CURLOPT_POSTFIELDSIZE_LARGE, offset: Int64(body.count))
            // COPYPOSTFIELDS copies exactly the size set above, so the bytes need not outlive this call. An empty body
            // still passes a valid pointer.
            let storage = body.isEmpty ? Data([0]) : body
            try storage.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws(CurlOptionError) in
                try easy.set(CURLOPT_COPYPOSTFIELDS, pointer: UnsafeMutableRawPointer(mutating: bytes.baseAddress))
            }
            if method != "POST" { try easy.set(CURLOPT_CUSTOMREQUEST, method) }
        }

        var lines = request.headers.map { header in
            header.value.isEmpty ? "\(header.name);" : "\(header.name): \(header.value)"
        }
        if request.header("User-Agent") == nil { lines.append("User-Agent: \(configuration.userAgent)") }
        // No 100-continue round trip for larger bodies, and no unrequested content type for bodies.
        lines.append("Expect:")
        if request.body != nil, request.header("Content-Type") == nil { lines.append("Content-Type:") }
        let list = try CurlStringList(lines)
        try easy.set(CURLOPT_HTTPHEADER, pointer: UnsafeMutableRawPointer(list.head))
        return list
    }

    private func check(_ code: Int32) throws(CurlOptionError) {
        guard code != 0 else { return }
        throw CurlOptionError(
            description:
                "libcurl refused a callback: \(String(cString: curl_easy_strerror(CURLcode(UInt32(bitPattern: code)))))"
        )
    }

    static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 1 }
        return Int(min(seconds, 86_400) * 1_000)
    }

    static func version(_ value: Int) -> HTTPVersion? {
        switch value {
        case Int(CURL_HTTP_VERSION_1_0): .http10
        case Int(CURL_HTTP_VERSION_1_1): .http11
        case Int(CURL_HTTP_VERSION_2_0): .http2
        case Int(CURL_HTTP_VERSION_3): .http3
        default: nil
        }
    }
}
