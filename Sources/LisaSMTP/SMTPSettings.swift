// The settings the SMTP email transport needs: the submission server and its TLS mode, the account, the address
// policy, and time and size limits.

import LisaCurl
import LisaHTTP
import LisaSecrets

/// How the SMTP transport reaches Lisa's submission server (EMAIL-01). The password is only a reference; the transport
/// resolves it at every send, so a missing secret is a classified failure rather than a startup crash.
public struct SMTPSettings: Hashable, Sendable {
    /// The largest `maxMessageBytes` accepted.
    public static let maxMessageBytesLimit = 10_485_760

    /// The SMTP server: a DNS name or an IP literal, without scheme, port or path.
    public var host: String
    public var port: Int
    /// Implicit TLS or a required STARTTLS upgrade; there is no plaintext mode, and certificates are always verified.
    public var security: CurlMailSecurity
    /// The SMTP account name.
    public var username: String
    /// The reference to the SMTP password.
    public var passwordSecret: SecretReference
    /// Which resolved addresses may be connected to. `.publicOnly` unless the configured host is a loopback or
    /// private-network IP literal (see ``addressPolicy(forHost:)``).
    public var addresses: AddressPolicy
    /// Name resolution, TCP and TLS setup.
    public var connectTimeoutSeconds: Double
    /// The longest wait for any single server reply.
    public var responseTimeoutSeconds: Int
    /// The whole submission, connection included. It should stay below the delivery lease, so that the outbox never
    /// treats a submission that is still running as abandoned.
    public var totalTimeoutSeconds: Double
    /// The largest composed message (headers and encoded body) the transport submits.
    public var maxMessageBytes: Int
    /// Test only: a PEM bundle that replaces the system trust store, for loopback verification against a synthetic
    /// certificate authority. Certificate and host-name verification stay on. Lisa's host leaves it `nil` in
    /// production.
    public var trustStorePath: String?

    public init(
        host: String, port: Int, security: CurlMailSecurity, username: String, passwordSecret: SecretReference,
        addresses: AddressPolicy = .publicOnly, connectTimeoutSeconds: Double = 15, responseTimeoutSeconds: Int = 30,
        totalTimeoutSeconds: Double = 60, maxMessageBytes: Int = 1_048_576, trustStorePath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.username = username
        self.passwordSecret = passwordSecret
        self.addresses = addresses
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.responseTimeoutSeconds = responseTimeoutSeconds
        self.totalTimeoutSeconds = totalTimeoutSeconds
        self.maxMessageBytes = maxMessageBytes
        self.trustStorePath = trustStorePath
    }

    /// The address policy for a configured server host: `.allowLocalNetworks` only when the host is written as a
    /// loopback or private-network IP literal, and `.publicOnly` for every DNS name, even one that resolves locally.
    public static func addressPolicy(forHost host: String) -> AddressPolicy {
        guard let address = IPLiteral.parse(unbracketed(host)) else { return .publicOnly }
        switch address.addressClass {
        case .loopback, .privateNetwork: return .allowLocalNetworks
        case .publicInternet, .linkLocal, .unspecified, .multicastOrBroadcast, .reserved: return .publicOnly
        }
    }

    /// What prevents sending with these settings; empty when they are usable. No entry contains a secret.
    public var problems: [String] {
        var found: [String] = []
        if !Self.isServerHost(host) { found.append("the SMTP host is not a valid host name or IP address") }
        if !(1...65_535).contains(port) { found.append("the SMTP port is not between 1 and 65535") }
        if username.isEmpty || username.utf8.count > 320
            || username.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        {
            found.append("the SMTP username is empty, longer than 320 bytes or contains control characters")
        }
        if !(connectTimeoutSeconds.isFinite && (1...120).contains(connectTimeoutSeconds)) {
            found.append("the SMTP connect timeout is not between 1 and 120 seconds")
        }
        if !(1...600).contains(responseTimeoutSeconds) {
            found.append("the SMTP response timeout is not between 1 and 600 seconds")
        }
        if !(totalTimeoutSeconds.isFinite && (1...600).contains(totalTimeoutSeconds)) {
            found.append("the SMTP submission timeout is not between 1 and 600 seconds")
        }
        if !(1_024...Self.maxMessageBytesLimit).contains(maxMessageBytes) {
            found.append("the SMTP message size limit is not between 1 KiB and 10 MiB")
        }
        if let path = trustStorePath, !path.hasPrefix("/") || path.unicodeScalars.contains(where: { $0.value == 0 }) {
            found.append("the SMTP trust store is not an absolute path")
        }
        return found
    }

    /// The server as LisaCurl reaches it.
    var server: CurlMailServer {
        CurlMailServer(
            host: host, port: port, security: security, addresses: addresses,
            connectTimeoutSeconds: connectTimeoutSeconds, responseTimeoutSeconds: responseTimeoutSeconds,
            trustStorePath: trustStorePath)
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }

    /// A DNS name of letters, digits, hyphens and underscores, or an IP literal (IPv6 optionally in brackets).
    static func isServerHost(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            return host.hasSuffix("]") && IPLiteral.parse(unbracketed(host))?.isIPv6 == true
        }
        if IPLiteral.parse(host) != nil { return true }
        var name = Substring(host)
        if name.hasSuffix(".") { name = name.dropLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let wellFormed = labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                        || byte == 0x2D || byte == 0x5F
                }
        }
        return wellFormed && !(labels.last?.utf8.allSatisfy { (0x30...0x39).contains($0) } ?? true)
    }
}
