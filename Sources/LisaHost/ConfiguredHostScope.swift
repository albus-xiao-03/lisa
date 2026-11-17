// The address policy for an endpoint the owner configured: local networks are allowed only when the configured host
// itself is a loopback or private literal (or localhost), and plain http only to loopback (SEC-02).

import Foundation
import LisaHTTP

enum ConfiguredHostScope {
    /// The policy for a configured server host, such as an IMAP or SMTP server.
    static func addressPolicy(forHost host: String) -> AddressPolicy {
        let name = host.lowercased()
        if name == "localhost" || name == "localhost." { return .allowLocalNetworks }
        let literal = name.hasPrefix("[") && name.hasSuffix("]") ? String(name.dropFirst().dropLast()) : name
        switch IPLiteral.parse(literal)?.addressClass {
        case .loopback, .privateNetwork: return .allowLocalNetworks
        default: return .publicOnly
        }
    }

    /// The policy for a configured endpoint URL: plain http is loopback-only; https follows its host.
    static func addressPolicy(forEndpoint url: URL) -> AddressPolicy {
        if url.scheme?.lowercased() == "http" { return .loopbackOnly }
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host else { return .publicOnly }
        return addressPolicy(forHost: host)
    }
}
