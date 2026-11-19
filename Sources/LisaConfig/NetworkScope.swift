// Where a configured address points: loopback, a private network, all interfaces, or anywhere else.

/// The reach of a configured network address, judged conservatively from its literal form alone, without DNS.
public enum NetworkScope: String, Hashable, Sendable {
    /// This machine only: 127.0.0.0/8, `::1` or the name `localhost`.
    case loopback
    /// A private or link-local network: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 (shared address
    /// space, used by some VPNs), 169.254.0.0/16, fc00::/7 or fe80::/10.
    case privateNetwork
    /// `0.0.0.0` or `::`: every interface, when binding.
    case unspecified
    /// Any other address, and every host name other than `localhost`.
    case publicNetwork

    /// The scope of `host`: an IP literal (brackets allowed) or a host name. Host names other than `localhost` are
    /// treated as public, because only DNS could say otherwise.
    static func of(host: String) -> NetworkScope {
        var literal = host
        if literal.hasPrefix("["), literal.hasSuffix("]") {
            literal = String(literal.dropFirst().dropLast())
        }
        if let address = IPAddress(literal) {
            return address.scope
        }
        let name = literal.lowercased()
        return name == "localhost" || name == "localhost." ? .loopback : .publicNetwork
    }
}
