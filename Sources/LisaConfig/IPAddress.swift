// IPv4 and IPv6 address literals: strict parsing and classification as loopback, private, unspecified or public.

import Foundation

/// An IPv4 or IPv6 address parsed from its literal text. Zone identifiers and brackets are not part of the literal.
struct IPAddress: Hashable, Sendable {
    /// 4 bytes for IPv4, 16 bytes for IPv6, in network order.
    let bytes: [UInt8]

    /// Parses a dotted-quad IPv4 address (no leading zeros) or an IPv6 address (with `::` and an optional trailing
    /// IPv4 part).
    init?(_ text: String) {
        if let bytes = Self.parseIPv4(Substring(text)) {
            self.bytes = bytes
        } else if let bytes = Self.parseIPv6(text) {
            self.bytes = bytes
        } else {
            return nil
        }
    }

    /// The address's reach, judged from the literal alone.
    var scope: NetworkScope {
        if bytes.count == 16 {
            // IPv4-mapped addresses (::ffff:a.b.c.d) are classified by their IPv4 part.
            if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
                return Self.ipv4Scope(Array(bytes[12..<16]))
            }
            return Self.ipv6Scope(bytes)
        }
        return Self.ipv4Scope(bytes)
    }

    private static func ipv4Scope(_ bytes: [UInt8]) -> NetworkScope {
        switch (bytes[0], bytes[1]) {
        case (127, _): .loopback
        case (0, _) where bytes.allSatisfy({ $0 == 0 }): .unspecified
        case (10, _), (172, 16...31), (192, 168), (169, 254), (100, 64...127): .privateNetwork
        default: .publicNetwork
        }
    }

    private static func ipv6Scope(_ bytes: [UInt8]) -> NetworkScope {
        if bytes.dropLast().allSatisfy({ $0 == 0 }) {
            switch bytes[15] {
            case 1: return .loopback
            case 0: return .unspecified
            default: return .publicNetwork
            }
        }
        // fc00::/7 unique local addresses and fe80::/10 link-local addresses.
        if bytes[0] & 0xFE == 0xFC || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) {
            return .privateNetwork
        }
        return .publicNetwork
    }

    private static func parseIPv4(_ text: Substring) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.utf8.count), part.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                part.utf8.count == 1 || part.first != "0", let value = UInt8(part)
            else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    private static func parseIPv6(_ text: String) -> [UInt8]? {
        guard text.contains(":"), text.utf8.count <= 45 else { return nil }
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        guard let head = groups(halves[0], allowsIPv4: halves.count == 1) else { return nil }
        var groupsValue = head
        if halves.count == 2 {
            guard let tail = groups(halves[1], allowsIPv4: true), head.count + tail.count <= 7 else { return nil }
            groupsValue = head + [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
        }
        guard groupsValue.count == 8 else { return nil }
        return groupsValue.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }

    /// The 16-bit groups of one side of `::`; a trailing dotted quad counts as two groups.
    private static func groups(_ text: String, allowsIPv4: Bool) -> [UInt16]? {
        guard !text.isEmpty else { return [] }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        var result: [UInt16] = []
        for (index, part) in parts.enumerated() {
            if index == parts.count - 1, allowsIPv4, part.contains("."), let quad = parseIPv4(part) {
                result.append(UInt16(quad[0]) << 8 | UInt16(quad[1]))
                result.append(UInt16(quad[2]) << 8 | UInt16(quad[3]))
                continue
            }
            // Integer parsing accepts a sign, so the digits are checked first.
            guard (1...4).contains(part.utf8.count), part.unicodeScalars.allSatisfy(\.properties.isASCIIHexDigit),
                let value = UInt16(part, radix: 16)
            else { return nil }
            result.append(value)
        }
        return result
    }
}
