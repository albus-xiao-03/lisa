// Random 128-bit identifiers on the wire (plan §8.1.1, §8.2.1): datasets, epochs, devices, enrollments,
// incarnations and operations.

/// A random 128-bit identifier. Its one wire form is 32 lowercase hexadecimal digits; anything else is refused.
public struct Identifier128: Hashable, Sendable, CustomStringConvertible {
    /// The 16 raw bytes, used where identifiers enter key derivations (plan §8.7).
    public let bytes: [UInt8]

    /// A new identifier from the system's cryptographically secure generator.
    public static func random() -> Identifier128 {
        var generator = SystemRandomNumberGenerator()
        return Identifier128(uncheckedBytes: (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    /// - Throws: `IdentifierError.invalidLength` unless `bytes` has exactly 16 bytes.
    public init(bytes: [UInt8]) throws(IdentifierError) {
        guard bytes.count == 16 else { throw .invalidLength(bytes.count) }
        self.bytes = bytes
    }

    init(uncheckedBytes: [UInt8]) {
        bytes = uncheckedBytes
    }

    /// Parses exactly 32 lowercase hexadecimal digits.
    public init(hex text: String) throws(IdentifierError) {
        self.bytes = try LowercaseHex.decode(text, byteCount: 16)
    }

    /// The 32 lowercase hexadecimal digits.
    public var hex: String { LowercaseHex.encode(bytes) }

    public var description: String { hex }
}
