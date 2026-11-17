// Classification of a resolved IPv4 or IPv6 address, from the special-purpose address registries (RFC 6890 and the
// documents it lists), for connect-time address checks (SEC-02).

/// What kind of destination a resolved address is.
public enum AddressClass: String, Hashable, Sendable {
    /// Globally routable.
    case publicInternet
    /// 127.0.0.0/8 and ::1.
    case loopback
    /// RFC 1918 private networks, IPv6 unique local addresses, and the 100.64.0.0/10 shared address space.
    case privateNetwork
    /// 169.254.0.0/16 and fe80::/10, which include cloud metadata services such as 169.254.169.254.
    case linkLocal
    /// 0.0.0.0/8 and ::.
    case unspecified
    /// 224.0.0.0/4, 255.255.255.255 and ff00::/8.
    case multicastOrBroadcast
    /// Documentation, benchmarking, protocol-assignment, translation, deprecated and reserved ranges, and IPv6
    /// addresses outside the global unicast range: never a legitimate service destination.
    case reserved
}

/// A resolved IPv4 or IPv6 address in network byte order.
public struct NetworkAddress: Hashable, Sendable, CustomStringConvertible {
    /// 4 bytes for IPv4, 16 bytes for IPv6.
    public let bytes: [UInt8]

    /// An address from its raw bytes; nil unless there are exactly 4 or 16.
    public init?(bytes: [UInt8]) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
    }

    public var isIPv6: Bool { bytes.count == 16 }

    public var description: String {
        if !isIPv6 { return bytes.map(String.init).joined(separator: ".") }
        return stride(from: 0, to: 16, by: 2).map { String(UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]), radix: 16) }
            .joined(separator: ":")
    }

    /// The address's class. IPv4-mapped (::ffff:0:0/96) and NAT64 well-known-prefix (64:ff9b::/96, RFC 6052)
    /// addresses are classified by the IPv4 address they carry.
    public var addressClass: AddressClass {
        isIPv6 ? Self.classifyIPv6(bytes) : Self.classifyIPv4(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    private static func classifyIPv4(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> AddressClass {
        switch (a, b, c) {
        case (0, _, _): return .unspecified  // 0.0.0.0/8 "this network"
        case (10, _, _), (172, 16...31, _), (192, 168, _): return .privateNetwork  // RFC 1918
        case (100, 64...127, _): return .privateNetwork  // RFC 6598 shared address space
        case (127, _, _): return .loopback
        case (169, 254, _): return .linkLocal  // RFC 3927
        case (192, 0, 0): return .reserved  // IETF protocol assignments
        case (192, 0, 2), (198, 51, 100), (203, 0, 113): return .reserved  // RFC 5737 documentation
        case (192, 88, 99): return .reserved  // RFC 7526 deprecated 6to4 relay anycast
        case (198, 18...19, _): return .reserved  // RFC 2544 benchmarking
        case (224...239, _, _): return .multicastOrBroadcast
        case (255, 255, 255) where d == 255: return .multicastOrBroadcast  // limited broadcast
        case (240...255, _, _): return .reserved  // RFC 1112 reserved
        default: return .publicInternet
        }
    }

    private static func classifyIPv6(_ bytes: [UInt8]) -> AddressClass {
        let prefixZero = bytes[0..<10].allSatisfy { $0 == 0 }
        if prefixZero, bytes[10] == 0, bytes[11] == 0, bytes[12] == 0, bytes[13] == 0, bytes[14] == 0 {
            switch bytes[15] {
            case 0: return .unspecified
            case 1: return .loopback
            default: return .reserved  // deprecated IPv4-compatible addresses
            }
        }
        if prefixZero, bytes[10] == 0xFF, bytes[11] == 0xFF {  // ::ffff:0:0/96 IPv4-mapped
            return classifyIPv4(bytes[12], bytes[13], bytes[14], bytes[15])
        }
        if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B, bytes[4..<12].allSatisfy({ $0 == 0 })
        {
            // 64:ff9b::/96 NAT64 well-known prefix: the embedded IPv4 address decides.
            return classifyIPv4(bytes[12], bytes[13], bytes[14], bytes[15])
        }
        if bytes[0] == 0xFF { return .multicastOrBroadcast }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .linkLocal }  // fe80::/10
        if bytes[0] & 0xFE == 0xFC { return .privateNetwork }  // fc00::/7 unique local
        // Only global unicast (2000::/3) can be a public destination; everything else is reserved or special.
        guard bytes[0] & 0xE0 == 0x20 else { return .reserved }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] & 0xFE == 0x00 {
            return .reserved  // 2001::/23 IETF protocol assignments (Teredo, benchmarking, ORCHID, ...)
        }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 { return .reserved }  // 2001:db8::/32
        if bytes[0] == 0x20, bytes[1] == 0x02 { return .reserved }  // 2002::/16 6to4
        if bytes[0] == 0x3F, bytes[1] == 0xFF, bytes[2] & 0xF0 == 0x00 { return .reserved }  // 3fff::/20 documentation
        return .publicInternet
    }
}

extension AddressPolicy {
    /// Whether a connection to `address` is allowed. Link-local, unspecified, multicast and reserved addresses are
    /// refused under every policy; loopback and private networks only for an explicitly configured local endpoint;
    /// and `loopbackOnly` allows loopback alone.
    public func permits(_ address: NetworkAddress) -> Bool {
        switch (self, address.addressClass) {
        case (.loopbackOnly, .loopback): true
        case (.loopbackOnly, _): false
        case (_, .publicInternet): true
        case (.allowLocalNetworks, .loopback), (.allowLocalNetworks, .privateNetwork): true
        default: false
        }
    }
}
