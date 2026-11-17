// What the libcurl mail paths share: the server to reach, how TLS is required, and classified failures that say
// whether a message or a command may have reached the server.

import LisaHTTP

/// How a mail connection is protected. There is no plaintext option, and certificates are always verified.
public enum CurlMailSecurity: Hashable, Sendable {
    /// TLS from the first byte (`imaps`, `smtps`).
    case implicitTLS
    /// A plaintext greeting upgraded with STARTTLS, which must succeed before anything else is sent.
    case startTLS
}

/// A mail server.
public struct CurlMailServer: Hashable, Sendable {
    public var host: String
    public var port: Int
    public var security: CurlMailSecurity
    /// Checked for every resolved address before connecting, and so before any credential is sent.
    public var addresses: AddressPolicy
    public var connectTimeoutSeconds: Double
    /// The longest wait for any single server response, including libcurl's own LOGOUT or QUIT when closing.
    public var responseTimeoutSeconds: Int
    /// A PEM bundle that replaces the system trust store; verification stays on. Lisa's host never sets it; it
    /// exists for loopback verification against a synthetic certificate authority.
    public var trustStorePath: String?

    public init(
        host: String, port: Int, security: CurlMailSecurity, addresses: AddressPolicy = .publicOnly,
        connectTimeoutSeconds: Double = 15, responseTimeoutSeconds: Int = 30, trustStorePath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.addresses = addresses
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.responseTimeoutSeconds = responseTimeoutSeconds
        self.trustStorePath = trustStorePath
    }

    /// Whether the host is a DNS name or an IP literal and the port is in range, so the URL built from them cannot
    /// carry anything else.
    public var isWellFormed: Bool {
        guard (1...65_535).contains(port), !host.isEmpty, host.utf8.count <= 253 else { return false }
        if IPLiteral.parse(host) != nil { return true }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                        || byte == 0x2D
                }
        }
    }

    /// The host as it appears in a URL, with IPv6 literals in brackets.
    var urlHost: String {
        host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }
}

/// Why a mail operation failed.
public enum CurlMailFailure: Error, Hashable, Sendable, CustomStringConvertible {
    /// Refused before connecting: no allowed address, or an invalid server or message.
    case refused(String)
    /// Name resolution, connection or TLS setup failed; no credential or message was sent.
    case notConnected(String)
    /// The server's certificate or name did not verify.
    case untrustedServer(String)
    /// STARTTLS was required but the server did not offer it or it failed; nothing else was sent.
    case startTLSUnavailable
    /// The server rejected the credentials.
    case authenticationFailed(String)
    /// The server refused the message or a command with this reply code; a 4xx code is temporary.
    case serverRefused(code: Int, String)
    /// The connection failed or timed out after a message was fully transmitted, so the server may have accepted
    /// it. Never retried automatically.
    case uncertain(String)
    /// The connection failed, timed out or closed before an operation completed; nothing was accepted.
    case connectionLost(String)
    /// The server's reply did not follow the protocol.
    case protocolError(String)
    /// The caller cancelled the operation.
    case cancelled

    public var description: String {
        switch self {
        case .refused(let reason): "refused: \(reason)"
        case .notConnected(let reason): "not connected: \(reason)"
        case .untrustedServer(let reason): "the server's certificate could not be verified: \(reason)"
        case .startTLSUnavailable: "the server did not complete the required STARTTLS upgrade"
        case .authenticationFailed(let reason): "authentication failed: \(reason)"
        case .serverRefused(let code, let reason): "the server refused with \(code): \(reason)"
        case .uncertain(let reason): "the outcome is unknown: \(reason)"
        case .connectionLost(let reason): "the connection was lost: \(reason)"
        case .protocolError(let reason): "protocol error: \(reason)"
        case .cancelled: "cancelled"
        }
    }
}
