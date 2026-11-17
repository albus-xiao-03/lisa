// Byte-level address checks: whether a peer or a bind address is loopback, including IPv4-mapped IPv6 peers on
// NIO's dual-stack sockets.

import NIOCore

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Address classification by raw bytes, never by text.
enum PeerAddress {
    /// Whether `address` is loopback: 127.0.0.0/8, `::1`, or `::ffff:127.x.x.x`. A missing address or a Unix
    /// domain socket is not loopback.
    static func isLoopback(_ address: SocketAddress?) -> Bool {
        switch address {
        case .v4(let v4):
            return isLoopback(ipv4: UInt32(bigEndian: v4.address.sin_addr.s_addr))
        case .v6(let v6):
            var raw = v6.address.sin6_addr
            let bytes = withUnsafeBytes(of: &raw) { Array($0) }
            return isLoopback(ipv6: bytes)
        default:
            return false
        }
    }

    static func isLoopback(ipv4 value: UInt32) -> Bool { value >> 24 == 127 }

    /// `::1`, or an IPv4-mapped loopback address (RFC 4291 §2.5.5.2).
    static func isLoopback(ipv6 bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
        let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        return mapped && bytes[12] == 127
    }

    /// Whether an IP literal names a loopback address; `nil` when it is not an IP literal.
    static func isLoopbackLiteral(_ text: String) -> Bool? {
        guard let address = try? SocketAddress(ipAddress: text, port: 0) else { return nil }
        return isLoopback(address)
    }
}
