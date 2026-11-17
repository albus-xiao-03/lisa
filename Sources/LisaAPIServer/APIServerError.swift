// Why the network server cannot start or serve; messages never contain key material or request content.

/// A server failure.
public enum APIServerError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The settings are unusable: an invalid address, an insecure listener or a bad limit.
    case invalidConfiguration(String)
    /// The TLS certificate chain or private key cannot be used.
    case invalidTLSMaterial(String)
    /// The address and port are already in use by another process.
    case addressInUse(address: String, port: Int)
    /// Binding failed for another reason.
    case bindFailed(address: String, port: Int, reason: String)
    /// `start()` was called on a server that already started or stopped.
    case notStartable

    public var description: String {
        switch self {
        case .invalidConfiguration(let reason): "the API server settings are invalid: \(reason)"
        case .invalidTLSMaterial(let reason): "the API TLS certificate or key cannot be used: \(reason)"
        case .addressInUse(let address, let port): "\(Self.endpoint(address, port)) is already in use"
        case .bindFailed(let address, let port, let reason):
            "the API server could not listen on \(Self.endpoint(address, port)): \(reason)"
        case .notStartable: "the API server has already been started"
        }
    }

    static func endpoint(_ address: String, _ port: Int) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}
