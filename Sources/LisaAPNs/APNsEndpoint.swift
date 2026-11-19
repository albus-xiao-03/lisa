// The fixed APNs provider endpoints: one host per environment on port 443, never taken from configuration (S10).

import Foundation
import LisaDomain

/// Where the APNs provider API of an environment is reached. Hosts and port are constants, so configuration can
/// never redirect pushes, and a token is only ever sent to its own environment (plan §6.2).
public struct APNsEndpoint: Hashable, Sendable {
    /// The HTTPS port. Apple also documents port 2197, which Lisa does not use.
    public static let port = 443

    public let environment: APNsEnvironment

    public init(_ environment: APNsEnvironment) {
        self.environment = environment
    }

    /// `api.sandbox.push.apple.com` for development (Apple's sandbox), `api.push.apple.com` for production.
    public var host: String {
        switch environment {
        case .development: "api.sandbox.push.apple.com"
        case .production: "api.push.apple.com"
        }
    }

    /// The scheme, host and port, as shown in diagnostics.
    public var origin: String { "https://\(host):\(Self.port)" }

    /// The request URL for one device, `https://<host>/3/device/<token>`; port 443 is the https default. Nil only if
    /// the URL cannot be formed, which a validated token never causes.
    public func url(for token: APNsDeviceToken) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/3/device/\(token.hex.revealed)"
        return components.url
    }
}
