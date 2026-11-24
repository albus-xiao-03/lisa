// Bounded ASCII tokens on the wire: R1 request IDs, scopes, discriminators and partitions (plan §8.12.2, §8.4.2).

/// Validation of short ASCII tokens carried in envelopes.
public enum WireText {
    /// R1's request-ID alphabet: `A-Z`, `a-z`, `0-9`, `.`, `_`, `:` and `-`.
    public static func isToken(_ text: String, length: ClosedRange<Int>) -> Bool {
        let bytes = Array(text.utf8)
        guard length.contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: ":"),
                UInt8(ascii: "-"):
                true
            default:
                false
            }
        }
    }

    /// The length range of an R1 `Lisa-Request-ID` (R1 `RequestID`: 8 to 128 characters).
    public static let requestIDLength = 8...128
    /// The length range of scopes, discriminators and partitions.
    public static let tokenLength = 1...128
}
