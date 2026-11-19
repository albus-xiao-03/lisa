// Deterministic APNs identifiers: the canonical lowercase UUID sent as `apns-id`, derived from the delivery ID, and
// the fixed-length `apns-collapse-id` digest of a collapse identity (S10; plan §6.4).

import Foundation
import LisaCrypto

/// Identifier derivation. Both values are SHA-256 based, so they reveal nothing of Lisa's own identifiers to Apple.
public enum APNsIdentifiers {
    /// Apple's limit for `apns-collapse-id`: "must not exceed 64 bytes".
    public static let maxCollapseIDBytes = 64

    /// A canonical lowercase UUID (32 hexadecimal digits in groups of 8-4-4-4-12) from SHA-256 of the delivery ID,
    /// with the RFC 9562 variant and version 8 bits. Every attempt of one delivery carries the same `apns-id`, so
    /// APNs responses and logs correlate with the outbox record. APNs is not documented to deduplicate by it.
    public static func apnsID(forDelivery deliveryID: String) -> String {
        var bytes = [UInt8](Digests.sha256(Data("lisa.apns-id.v1:\(deliveryID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map(hexByte)
        // 4, 2, 2, 2 and 6 bytes give the 8-4-4-4-12 digit groups.
        return [0..<4, 4..<6, 6..<8, 8..<10, 10..<16].map { hex[$0].joined() }.joined(separator: "-")
    }

    /// 32 lowercase hexadecimal digits from SHA-256 of the collapse identity: a fixed length well within Apple's 64
    /// bytes, the same for every device and attempt of one occurrence (or subject, for changes).
    public static func collapseID(for identity: String) -> String {
        Digests.sha256(Data("lisa.apns-collapse-id.v1:\(identity)".utf8)).prefix(16).map(hexByte).joined()
    }

    /// Whether `text` is a canonical UUID: hexadecimal digits in groups of 8-4-4-4-12 (either case).
    public static func isCanonicalUUID(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        return groups.map(\.utf8.count) == [8, 4, 4, 4, 12]
            && groups.allSatisfy { group in
                group.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
                }
            }
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let digits = Array("0123456789abcdef".utf8)
        return String(decoding: [digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]], as: UTF8.self)
    }
}
