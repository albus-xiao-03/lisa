// The options every mail connection gets: the URL and allowed protocol, required TLS with verification, no proxy,
// connect-time address checks, credentials, and time limits.

import CCurl
import CCurlShim

enum CurlMailOptions {
    /// Configures `easy` to reach `server` with `scheme` ("imap" or "smtp"); `path` follows the authority.
    static func apply(
        to easy: CurlEasy, server: CurlMailServer, scheme: String, path: String, username: String, password: String,
        gate: CurlAddressGate, transfer: CurlTransfer, cancellation: CurlCancellation, totalTimeoutSeconds: Double
    ) throws(CurlOptionError) {
        let secureScheme = server.security == .implicitTLS ? "\(scheme)s" : scheme
        try easy.set(CURLOPT_URL, "\(secureScheme)://\(server.urlHost):\(server.port)/\(path)")
        try easy.set(CURLOPT_PROTOCOLS_STR, secureScheme)
        if server.security == .startTLS {
            // STARTTLS must succeed before anything else is sent, or the transfer fails (CURLE_USE_SSL_FAILED).
            try easy.set(CURLOPT_USE_SSL, Int(CURLUSESSL_ALL))
        }
        try easy.set(CURLOPT_PROXY, "")
        try easy.set(CURLOPT_NOSIGNAL, 1)
        try easy.set(CURLOPT_SSLVERSION, Int(CURL_SSLVERSION_TLSv1_2))
        try easy.set(CURLOPT_SSL_VERIFYPEER, 1)
        try easy.set(CURLOPT_SSL_VERIFYHOST, 2)
        if let trustStore = server.trustStorePath { try easy.set(CURLOPT_CAINFO, trustStore) }
        try easy.set(CURLOPT_USERNAME, username)
        try easy.set(CURLOPT_PASSWORD, password)
        try easy.set(CURLOPT_CONNECTTIMEOUT_MS, CurlHTTPExchange.milliseconds(server.connectTimeoutSeconds))
        try easy.set(CURLOPT_TIMEOUT_MS, CurlHTTPExchange.milliseconds(totalTimeoutSeconds))
        try easy.set(CURLOPT_SERVER_RESPONSE_TIMEOUT, max(1, server.responseTimeoutSeconds))
        try require(lisa_curl_install_address_gate(easy.handle, gate.cGate))
        try require(lisa_curl_set_abort_check(easy.handle, cancellation.binding))
        try require(lisa_curl_set_header_callback(easy.handle, curlWriteHeader, transfer.userdata))
    }

    static func require(_ code: Int32) throws(CurlOptionError) {
        guard code != 0 else { return }
        throw CurlOptionError(
            description:
                "libcurl refused a callback: \(String(cString: curl_easy_strerror(CURLcode(UInt32(bitPattern: code)))))"
        )
    }

    /// The failure for a mail connection setup that ended with `code`, before any message was sent.
    static func setupFailure(_ code: CURLcode, message: String, gate: CurlAddressGate, cancelled: Bool)
        -> CurlMailFailure
    {
        switch code {
        case _ where cancelled: .cancelled
        case CURLE_COULDNT_RESOLVE_HOST: .notConnected("the host name could not be resolved")
        case CURLE_COULDNT_CONNECT where !gate.refusedClasses.isEmpty:
            .refused(
                "the host resolves only to addresses Lisa does not connect to ("
                    + Array(Set(gate.refusedClasses.map(\.rawValue))).sorted().joined(separator: ", ") + ")")
        case CURLE_COULDNT_CONNECT: .notConnected("the connection could not be established")
        case CURLE_PEER_FAILED_VERIFICATION: .untrustedServer(message)
        case CURLE_SSL_CONNECT_ERROR, CURLE_SSL_CACERT_BADFILE: .notConnected("TLS setup failed: \(message)")
        case CURLE_USE_SSL_FAILED: .startTLSUnavailable
        case CURLE_LOGIN_DENIED: .authenticationFailed(message)
        case CURLE_OPERATION_TIMEDOUT: .connectionLost("timed out: \(message)")
        case CURLE_WEIRD_SERVER_REPLY: .protocolError(message)
        case CURLE_UNSUPPORTED_PROTOCOL: .refused("libcurl does not support this mail protocol: \(message)")
        default: .connectionLost(message)
        }
    }
}
