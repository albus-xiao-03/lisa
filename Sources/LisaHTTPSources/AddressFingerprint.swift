// A stable fingerprint that ties stored validators to the non-secret parts of the address they came from.

/// FNV-1a over UTF-8 bytes, printed as 16 hexadecimal digits. Unlike `Hasher`, it is the same in every process, so a
/// fingerprint stored in a cursor stays comparable across restarts. ``AddressResolution`` computes it only over text
/// that holds no secret.
package enum AddressFingerprint {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    package static func hex(_ text: String) -> String {
        var hash = offsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
