// Where and how the host serves its network API (API-01), from the `api` configuration section.

import LisaSecrets

/// The device listener's address, port and protection. The owner listener for the CLI in client mode is always plain
/// HTTP on 127.0.0.1 with a free port.
public struct APIServerSettings: Hashable, Sendable {
    /// How the device listener is protected in transit.
    public enum Protection: Hashable, Sendable {
        /// Plain HTTP; the bind address must be loopback.
        case none
        /// TLS served by Lisa with the referenced PEM certificate chain and unencrypted PEM private key.
        case native(certificateChain: SecretReference, privateKey: SecretReference)
        /// Plain HTTP to a trusted reverse proxy that terminates TLS; no request counts as coming from this machine.
        case reverseProxy
    }

    /// An IPv4 or IPv6 literal.
    public var bindAddress: String
    public var port: Int
    public var protection: Protection

    public init(bindAddress: String = "127.0.0.1", port: Int = 8765, protection: Protection = .none) {
        self.bindAddress = bindAddress
        self.port = port
        self.protection = protection
    }
}
