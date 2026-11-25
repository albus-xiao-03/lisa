// The validated base address of a Lisa host's API: https, or http only to a loopback host, with an optional path prefix.

import Foundation
import LisaAPIContract

/// The base address of a Lisa host's API (API-01), such as `https://lisa.example.net`, `https://example.net/lisa`
/// behind a reverse proxy, or `http://127.0.0.1:8765` on the same machine.
///
/// - The scheme is `https`. Plain `http` is accepted only for a loopback host: an IPv4 address in 127.0.0.0/8, the
///   IPv6 address `::1` or the name `localhost`.
/// - The address has a host, an optional port and an optional path prefix. It carries no user name, password, query
///   or fragment.
/// - Host names are ASCII (international names in their punycode form) and are kept in lowercase. IP addresses must
///   be literal: dotted-decimal IPv4 without leading zeros, or IPv6 in brackets without a zone.
public struct HostEndpoint: Hashable, Sendable, CustomStringConvertible {
    /// The scheme of an endpoint.
    public enum Scheme: String, Hashable, Sendable {
        case https
        case http

        /// The port used when the address names none.
        public var defaultPort: Int {
            switch self {
            case .https: 443
            case .http: 80
            }
        }
    }

    /// `https`, or `http` for a loopback host.
    public let scheme: Scheme
    /// The host in lowercase: a DNS name, an IPv4 address, or an IPv6 address without brackets.
    public let host: String
    /// The port, or `nil` for the scheme's default port.
    public let port: Int?
    /// A reverse proxy's sub-path such as `/lisa`, without a trailing slash, or empty.
    public let pathPrefix: String
    /// Whether the host is this machine: 127.0.0.0/8, `::1` or `localhost`. Only then is `http` allowed.
    public let isLoopback: Bool

    /// Parses and checks a host address such as `https://lisa.example.net` or `http://[::1]:8765`. A single trailing
    /// slash is dropped; a port equal to the scheme's default is dropped too.
    ///
    /// - Throws: `HostEndpointError`. Its description never repeats `text`, which might contain a password.
    public init(parsing text: String) throws(HostEndpointError) {
        guard !text.isEmpty else { throw .malformed("the address is empty") }
        guard text.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else {
            throw .malformed(
                "the address contains a space, a control character or a non-ASCII character (write international "
                    + "host names in their punycode form)")
        }
        guard let separator = text.range(of: "://") else {
            throw .malformed("expected an absolute address such as https://lisa.example.net")
        }
        guard let scheme = Scheme(rawValue: text[..<separator.lowerBound].lowercased()) else {
            throw .unsupportedScheme
        }
        let remainder = text[separator.upperBound...]
        guard !remainder.contains("?"), !remainder.contains("#") else { throw .queryOrFragment }
        let authority = remainder.prefix { $0 != "/" }
        guard !authority.contains("@") else { throw .userInfo }
        let parsed = try Self.parseAuthority(authority)
        guard scheme == .https || parsed.isLoopback else { throw .plaintextToRemoteHost }
        self.scheme = scheme
        host = parsed.host
        port = parsed.port == scheme.defaultPort ? nil : parsed.port
        pathPrefix = try Self.parsePathPrefix(remainder[authority.endIndex...])
        isLoopback = parsed.isLoopback
    }

    /// The port connections use.
    public var effectivePort: Int { port ?? scheme.defaultPort }

    /// The base address, for example `https://example.net/lisa` or `http://[::1]:8765`.
    public var description: String {
        let authority = host.contains(":") ? "[\(host)]" : host
        let port = port.map { ":\($0)" } ?? ""
        return "\(scheme.rawValue)://\(authority)\(port)\(pathPrefix)"
    }

    /// The URL of `request` on this host: the base address followed by the request's origin-form target, whose path
    /// segments and query items are percent-encoded (`APIRequest.encodedTarget()`).
    ///
    /// - Throws: `APITransportError.refused` when the path does not start with `/v1/` or is not usable.
    public func url(for request: APIRequest) throws(APITransportError) -> URL {
        let apiPrefix = APIVersioning.pathPrefix + "/"
        // R2 extends the shared transport to the v2 routes (plan §8.6.5).
        guard request.path.hasPrefix(apiPrefix) || request.path.hasPrefix("/v2/") else {
            throw .refused("the request path does not start with \(apiPrefix) or /v2/")
        }
        guard let target = request.encodedTarget() else {
            throw .refused(
                "the request path has an empty, \".\" or \"..\" segment, or contains \"?\", \"#\" or a control "
                    + "character")
        }
        guard let url = URL(string: description + target) else {
            throw .refused("the request URL could not be formed")
        }
        return url
    }

    // MARK: - Parsing

    /// The host, whether it is a loopback host, and the port of `authority`: `host`, `host:port`, `[v6]` or
    /// `[v6]:port`.
    private static func parseAuthority(
        _ authority: Substring
    ) throws(HostEndpointError) -> (host: String, isLoopback: Bool, port: Int?) {
        let host: Substring
        let portText: Substring?
        let isLoopback: Bool
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else {
                throw .invalidHost("an IPv6 address is missing its closing bracket")
            }
            host = authority[authority.index(after: authority.startIndex)..<close]
            let rest = authority[authority.index(after: close)...]
            if rest.isEmpty {
                portText = nil
            } else if rest.hasPrefix(":") {
                portText = rest.dropFirst()
            } else {
                throw .invalidHost("unexpected text after the IPv6 address")
            }
            guard let words = ipv6Words(host) else { throw .invalidHost("the IPv6 address is not valid") }
            guard words.contains(where: { $0 != 0 }) else {
                throw .invalidHost("the unspecified address :: cannot be connected to")
            }
            isLoopback = words == [0, 0, 0, 0, 0, 0, 0, 1]
        } else {
            let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else {
                throw .invalidHost("an IPv6 address must be written in brackets, such as [::1]")
            }
            host = parts[0]
            portText = parts.count == 2 ? parts[1] : nil
            guard !host.isEmpty else { throw .invalidHost("the host is missing") }
            if host.utf8.allSatisfy({ isDigit($0) || $0 == UInt8(ascii: ".") }) {
                guard let octets = ipv4Octets(host) else { throw .invalidHost("the IPv4 address is not valid") }
                guard octets != [0, 0, 0, 0] else {
                    throw .invalidHost("the unspecified address 0.0.0.0 cannot be connected to")
                }
                isLoopback = octets[0] == 127
            } else {
                guard isHostName(host) else { throw .invalidHost("the host name is not valid") }
                isLoopback = host.lowercased() == "localhost"
            }
        }
        var port: Int?
        if let portText { port = try parsePort(portText) }
        return (host.lowercased(), isLoopback, port)
    }

    /// A port from 1 to 65535 written in decimal digits.
    private static func parsePort(_ text: Substring) throws(HostEndpointError) -> Int {
        guard (1...5).contains(text.utf8.count), text.utf8.allSatisfy(isDigit), let port = Int(text),
            (1...65_535).contains(port)
        else { throw .invalidPort }
        return port
    }

    /// The path prefix of `path`, which is empty or starts with `/`, without one trailing slash.
    private static func parsePathPrefix(_ path: Substring) throws(HostEndpointError) -> String {
        let trimmed = path.hasSuffix("/") ? path.dropLast() : path
        guard !trimmed.isEmpty else { return "" }
        let segments = trimmed.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard segments.allSatisfy(isPathSegment) else { throw .invalidPathPrefix }
        return String(trimmed)
    }

    /// Whether `segment` is a non-empty path segment other than `.` and `..` made of RFC 3986 unreserved characters.
    private static func isPathSegment(_ segment: Substring) -> Bool {
        guard !segment.isEmpty, segment != ".", segment != ".." else { return false }
        return segment.utf8.allSatisfy { byte in
            isAlphanumeric(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
                || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "~")
        }
    }

    /// Whether `text` is a DNS host name: dot-separated labels of letters, digits and inner hyphens, at most 63
    /// characters each and 253 in total, without a trailing dot.
    private static func isHostName(_ text: Substring) -> Bool {
        guard text.utf8.count <= 253 else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { isAlphanumeric($0) || $0 == UInt8(ascii: "-") }
        }
    }

    /// The four octets of a dotted-decimal IPv4 address without leading zeros, such as `127.0.0.1`.
    private static func ipv4Octets(_ text: Substring) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.utf8.count), part.utf8.allSatisfy(isDigit),
                part.count == 1 || part.first != "0", let octet = UInt8(part)
            else { return nil }
            octets.append(octet)
        }
        return octets
    }

    /// The eight 16-bit words of an IPv6 address in RFC 4291 text form, which may end in a dotted IPv4 address.
    /// Zone identifiers are not accepted.
    private static func ipv6Words(_ text: Substring) -> [UInt16]? {
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2, let head = ipv6Groups(halves[0], mayEndInIPv4: halves.count == 1) else { return nil }
        guard halves.count == 2 else { return head.count == 8 ? head : nil }
        guard let tail = ipv6Groups(halves[1], mayEndInIPv4: true), head.count + tail.count <= 7 else { return nil }
        return head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
    }

    /// The words of colon-separated groups of one to four hexadecimal digits, the last of which may be a dotted IPv4
    /// address; no words for empty text.
    private static func ipv6Groups(_ text: String, mayEndInIPv4: Bool) -> [UInt16]? {
        guard !text.isEmpty else { return [] }
        let groups = text.split(separator: ":", omittingEmptySubsequences: false)
        var words: [UInt16] = []
        for (index, group) in groups.enumerated() {
            if mayEndInIPv4, index == groups.count - 1, group.contains(".") {
                guard let octets = ipv4Octets(group) else { return nil }
                words.append(UInt16(octets[0]) << 8 | UInt16(octets[1]))
                words.append(UInt16(octets[2]) << 8 | UInt16(octets[3]))
            } else {
                guard (1...4).contains(group.utf8.count), group.utf8.allSatisfy(isHexDigit),
                    let word = UInt16(group, radix: 16)
                else { return nil }
                words.append(word)
            }
        }
        return words
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
    }
}
