// Strict parsing of IPv4 dotted-quad and IPv6 address literals into NetworkAddress values.

/// Parses address literals. IPv4 accepts only four decimal parts without leading zeros, so octal and hexadecimal
/// spellings that resolvers interpret differently are never accepted.
public enum IPLiteral {
    public static func parse(_ text: String) -> NetworkAddress? {
        if let bytes = ipv4(Substring(text)) { return NetworkAddress(bytes: bytes) }
        if let bytes = ipv6(text) { return NetworkAddress(bytes: bytes) }
        return nil
    }

    static func ipv4(_ text: Substring) -> [UInt8]? {
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

    static func ipv6(_ text: String) -> [UInt8]? {
        guard text.contains(":"), text.utf8.count <= 45 else { return nil }
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        guard let head = groups(halves[0], allowsIPv4: halves.count == 1) else { return nil }
        var all = head
        if halves.count == 2 {
            guard let tail = groups(halves[1], allowsIPv4: true), head.count + tail.count <= 7 else { return nil }
            all = head + [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
        }
        guard all.count == 8 else { return nil }
        return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }

    private static func groups(_ text: String, allowsIPv4: Bool) -> [UInt16]? {
        guard !text.isEmpty else { return [] }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        var result: [UInt16] = []
        for (index, part) in parts.enumerated() {
            if index == parts.count - 1, allowsIPv4, part.contains(".") {
                guard let quad = ipv4(part) else { return nil }
                result.append(UInt16(quad[0]) << 8 | UInt16(quad[1]))
                result.append(UInt16(quad[2]) << 8 | UInt16(quad[3]))
                continue
            }
            guard (1...4).contains(part.utf8.count), part.unicodeScalars.allSatisfy(\.properties.isASCIIHexDigit),
                let value = UInt16(part, radix: 16)
            else { return nil }
            result.append(value)
        }
        return result
    }
}
