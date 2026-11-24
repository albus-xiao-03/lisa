// 32-byte SHA-256 values on the wire: digests, fingerprints and pins (plan §8.1.1, §8.1.2).

/// A 32-byte SHA-256 value. Its one wire form is 64 lowercase hexadecimal digits; anything else is refused.
public struct Digest256: Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    /// - Throws: `IdentifierError.invalidLength` unless `bytes` has exactly 32 bytes.
    public init(bytes: [UInt8]) throws(IdentifierError) {
        guard bytes.count == 32 else { throw .invalidLength(bytes.count) }
        self.bytes = bytes
    }

    /// Parses exactly 64 lowercase hexadecimal digits.
    public init(hex text: String) throws(IdentifierError) {
        self.bytes = try LowercaseHex.decode(text, byteCount: 32)
    }

    /// The 64 lowercase hexadecimal digits.
    public var hex: String { LowercaseHex.encode(bytes) }

    public var description: String { hex }
}
