// Strict lowercase hexadecimal, the only spelling identifiers and digests travel in (plan §8.1.1).

/// Encodes bytes as lowercase hexadecimal and decodes only that exact spelling.
enum LowercaseHex {
    static let digits = Array("0123456789abcdef".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// - Throws: `IdentifierError` unless `text` is exactly `byteCount * 2` lowercase hexadecimal digits.
    static func decode(_ text: String, byteCount: Int) throws(IdentifierError) -> [UInt8] {
        let input = Array(text.utf8)
        guard input.count == byteCount * 2 else { throw .invalidLength(input.count) }
        var out: [UInt8] = []
        out.reserveCapacity(byteCount)
        var index = 0
        while index < input.count {
            guard let high = nibble(input[index]), let low = nibble(input[index + 1]) else { throw .invalidHex }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}
