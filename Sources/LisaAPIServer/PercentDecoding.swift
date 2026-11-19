// Strict percent-decoding of request-target components (RFC 3986 §2.1): every `%` starts a two-digit escape, `+` is
// not a space, the result must be UTF-8, and control characters are refused.

enum PercentDecoding {
    /// The decoded text, or `nil` for a malformed escape, invalid UTF-8 or a control character.
    static func decode(_ text: Substring) -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "%") else {
                bytes.append(byte)
                continue
            }
            guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else {
                return nil
            }
            bytes.append(high << 4 | low)
        }
        guard let decoded = String(validating: bytes, as: UTF8.self) else { return nil }
        guard !decoded.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return decoded
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
