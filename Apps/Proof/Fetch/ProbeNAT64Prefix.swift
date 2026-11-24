// PROOF ONLY — Apps/Proof never ships. NAT64 prefix arithmetic for the E-1 probe (plan §8.9.3; RFC 6052 §2.2
// address format, RFC 7050 §3 discovery): find the well-known IPv4 addresses 192.0.0.170/171 at the octet
// boundaries of a synthesized `ipv4only.arpa` answer, and embed or extract an IPv4 address under a prefix. Pure logic;
// M7's portable destination policy is to own it (docs/DECISIONS.md D-54).

struct ProbeNAT64Prefix: Codable, Sendable, Equatable, Hashable {
    /// The prefix's leading bytes (`length / 8` of them).
    let bytes: [UInt8]
    /// 32, 40, 48, 56, 64 or 96.
    let length: Int

    static let wellKnown = ProbeNAT64Prefix(bytes: [0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0], length: 96)
    /// RFC 8215's local-use 64:ff9b:1::/48 container (its embedding length is not fixed; docs/DECISIONS.md D-54).
    static let localUseContainer: [UInt8] = [0x00, 0x64, 0xFF, 0x9B, 0x00, 0x01]
    /// Where the four IPv4 bytes sit for each prefix length (byte 8, the "u" octet, is skipped and must be zero).
    static let positions: [Int: [Int]] = [
        32: [4, 5, 6, 7], 40: [5, 6, 7, 9], 48: [6, 7, 9, 10], 56: [7, 9, 10, 11], 64: [9, 10, 11, 12],
        96: [12, 13, 14, 15],
    ]
    static let wellKnownIPv4: [[UInt8]] = [[192, 0, 0, 170], [192, 0, 0, 171]]

    /// The prefixes of synthesized answers, in the order received, without duplicates. An answer in which a
    /// well-known address appears at more than one boundary is ambiguous and yields nothing.
    static func discover(fromSynthesized answers: [[UInt8]]) -> [ProbeNAT64Prefix] {
        var found: [ProbeNAT64Prefix] = []
        for answer in answers where answer.count == 16 {
            let matches = positions.keys.sorted().filter { length in
                let places = positions[length]!
                guard length == 32 || length == 96 || answer[8] == 0 else { return false }
                return wellKnownIPv4.contains(places.map { answer[$0] })
            }
            guard matches.count == 1, let length = matches.first else { continue }
            let prefix = ProbeNAT64Prefix(bytes: Array(answer.prefix(length / 8)), length: length)
            if !found.contains(prefix) { found.append(prefix) }
        }
        return found
    }

    func contains(_ address: [UInt8]) -> Bool {
        guard address.count == 16, Array(address.prefix(length / 8)) == bytes else { return false }
        return length == 32 || length == 96 || address[8] == 0
    }

    /// The embedded IPv4 address of an address under this prefix.
    func embeddedIPv4(_ address: [UInt8]) -> [UInt8]? {
        guard contains(address), let places = Self.positions[length] else { return nil }
        return places.map { address[$0] }
    }

    /// The IPv6 address that carries `ipv4` under this prefix (u octet and suffix zero).
    func synthesize(_ ipv4: [UInt8]) -> [UInt8] {
        var address = bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
        for (offset, place) in (Self.positions[length] ?? []).enumerated() { address[place] = ipv4[offset] }
        return address
    }

    var text: String {
        let padded = bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
        let groups = stride(from: 0, to: 16, by: 2).map {
            String(UInt16(padded[$0]) << 8 | UInt16(padded[$0 + 1]), radix: 16)
        }
        return groups.joined(separator: ":") + "/\(length)"
    }
}
