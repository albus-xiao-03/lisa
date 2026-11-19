// Rules for the URLs Lisa requests (SEC-02): https only (plain http only to a loopback model server), no embedded
// credentials, a well-formed host, and nothing that could smuggle a second request.

import Foundation

/// Validates request URLs before anything is sent. Every connector, transport and redirect hop goes through it.
public enum URLPolicy {
    /// The longest URL Lisa requests.
    public static let maxURLLength = 8_192

    /// Checks `url` for a request under `addresses`; returns the URL without a fragment, or why it is refused.
    public static func validate(_ url: URL, addresses: AddressPolicy) -> Result<URL, HTTPFailure> {
        let text = url.absoluteString
        guard text.utf8.count <= maxURLLength else { return .failure(.refused("the address is too long")) }
        guard !text.utf8.contains(where: { $0 <= 0x20 || $0 == 0x7F }) else {
            return .failure(.refused("the address contains spaces or control characters"))
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let scheme = components.scheme?.lowercased()
        else { return .failure(.refused("the address is not a complete URL")) }
        guard components.user == nil, components.password == nil else {
            return .failure(.refused("the address contains a user name or password"))
        }
        guard let host = components.host, !host.isEmpty, isWellFormedHost(host) else {
            return .failure(.refused("the address does not name a valid host"))
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return .failure(.refused("the address names an invalid port"))
        }
        switch scheme {
        case "https":
            break
        case "http" where addresses == .loopbackOnly && isLoopbackName(host):
            break
        case "http":
            return .failure(
                .refused(
                    "plain http is not allowed; use https (plain http is accepted only for a loopback model endpoint)"))
        default:
            return .failure(.refused("only https addresses are requested"))
        }
        components.fragment = nil
        guard let cleaned = components.url else { return .failure(.refused("the address is not a complete URL")) }
        return .success(cleaned)
    }

    /// The scheme, host and port of `url`, which is all that is ever logged of an address.
    public static func origin(of url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true), let host = components.host
        else { return "(invalid address)" }
        let scheme = components.scheme?.lowercased() ?? "?"
        return components.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// Whether two URLs share scheme, host and port.
    public static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let a = URLComponents(url: first, resolvingAgainstBaseURL: true),
            let b = URLComponents(url: second, resolvingAgainstBaseURL: true)
        else { return false }
        return a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && effectivePort(a) == effectivePort(b)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// `localhost`, or a literal loopback address.
    static func isLoopbackName(_ host: String) -> Bool {
        var name = host.lowercased()
        if name == "localhost" || name == "localhost." { return true }
        // URLComponents keeps the brackets of an IPv6 literal, as in http://[::1]:8080.
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        return IPLiteral.parse(name).map { $0.addressClass == .loopback } ?? false
    }

    /// A DNS name (ASCII letters, digits, hyphens and underscores in dot-separated labels) or an IP literal; IPv6
    /// literals in brackets, without a zone identifier.
    static func isWellFormedHost(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            guard host.hasSuffix("]") else { return false }
            let inner = String(host.dropFirst().dropLast())
            return !inner.contains("%") && IPLiteral.parse(inner)?.isIPv6 == true
        }
        if IPLiteral.parse(host) != nil { return true }
        var name = Substring(host)
        if name.hasSuffix(".") { name = name.dropLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                        || byte == 0x2D || byte == 0x5F
                }
        }
    }
}
