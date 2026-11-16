// The `api` section: the host API's bind address, port, TLS arrangement and idempotency-record retention.

import LisaSecrets

/// How the host API is protected in transit (API-01).
public enum APITLSMode: String, Hashable, Sendable, CaseIterable {
    /// Plain HTTP; allowed only on a loopback bind address.
    case none
    /// TLS served by Lisa with the referenced certificate and private key.
    case native
    /// Plain HTTP to a trusted reverse proxy that terminates TLS; the bind address must be loopback or private.
    case reverseProxy
}

/// The TLS arrangement of the host API.
public struct APITLSConfiguration: Hashable, Sendable {
    /// No TLS (loopback only), native TLS, or a trusted reverse proxy.
    public let mode: APITLSMode
    /// The reference to the PEM certificate chain; required for `native`.
    public let certificateSecret: SecretReference?
    /// The reference to the PEM private key; required for `native`.
    public let privateKeySecret: SecretReference?

    static func decode(_ section: ConfigSection?) -> APITLSConfiguration {
        let defaults = APIConfiguration.defaultValue.tls
        guard let section else { return defaults }
        defer { section.finish() }
        return APITLSConfiguration(
            mode: section.choice("mode", default: defaults.mode, options: APITLSMode.allCases),
            certificateSecret: section.secret("certificateSecret"),
            privateKeySecret: section.secret("privateKeySecret"))
    }
}

/// The host API (API-01, API-03). Every client authenticates with its own revocable device credential; there is no
/// setting that turns authentication off. Binding beyond loopback needs native TLS or a trusted reverse proxy.
public struct APIConfiguration: Hashable, Sendable {
    /// The IP address the API listens on; `127.0.0.1` by default.
    public let bindAddress: String
    /// The reach of `bindAddress`.
    public let bindScope: NetworkScope
    /// The TCP port; 8765 by default.
    public let port: Int
    /// How the API is protected in transit.
    public let tls: APITLSConfiguration
    /// How long idempotency records of mutating requests are kept; at least the clients' 30-day maximum offline
    /// retry period, so a late retry is never applied twice.
    public let idempotencyRetentionDays: Int

    /// The documented maximum offline retry period of clients, which idempotency records must outlive.
    public static let minimumIdempotencyRetentionDays = 30

    /// Loopback on port 8765, no TLS, and 30 days of idempotency records.
    public static let defaultValue = APIConfiguration(
        bindAddress: "127.0.0.1", bindScope: .loopback, port: 8765,
        tls: APITLSConfiguration(mode: .none, certificateSecret: nil, privateKeySecret: nil),
        idempotencyRetentionDays: minimumIdempotencyRetentionDays)

    /// Whether the API is reachable from this machine only.
    public var isLoopbackOnly: Bool { bindScope == .loopback }

    static func decode(_ section: ConfigSection?) -> APIConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        var bindAddress = defaults.bindAddress
        var bindScope = defaults.bindScope
        if let value = section.value("bindAddress"),
            let scope = value.validated(maxLength: 45, NetworkAddressRules.bindAddress),
            case .string(let text) = value.node.value
        {
            bindAddress = text
            bindScope = scope
        }
        return APIConfiguration(
            bindAddress: bindAddress,
            bindScope: bindScope,
            port: section.integer("port", default: defaults.port, in: 1...65_535),
            tls: APITLSConfiguration.decode(section.section("tls")),
            idempotencyRetentionDays: section.integer(
                "idempotencyRetentionDays", default: defaults.idempotencyRetentionDays,
                in: minimumIdempotencyRetentionDays...3650))
    }
}
