// Unpadded base64url (RFC 4648 §5) with one accepted spelling per byte string (plan §8.16.1, §8.1.2).

/// Encodes and strictly decodes unpadded base64url. Decoding refuses padding, characters outside the alphabet, an
/// impossible length and non-zero unused trailing bits, so every byte string has exactly one accepted encoding.
public enum StrictBase64URL {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// The unpadded base64url text of `bytes`.
    public static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count * 4 + 2) / 3)
        var index = 0
        while index + 3 <= bytes.count {
            let chunk = UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2])
            out.append(alphabet[Int(chunk >> 18 & 63)])
            out.append(alphabet[Int(chunk >> 12 & 63)])
            out.append(alphabet[Int(chunk >> 6 & 63)])
            out.append(alphabet[Int(chunk & 63)])
            index += 3
        }
        switch bytes.count - index {
        case 1:
            let chunk = UInt32(bytes[index]) << 16
            out.append(alphabet[Int(chunk >> 18 & 63)])
            out.append(alphabet[Int(chunk >> 12 & 63)])
        case 2:
            let chunk = UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8
            out.append(alphabet[Int(chunk >> 18 & 63)])
            out.append(alphabet[Int(chunk >> 12 & 63)])
            out.append(alphabet[Int(chunk >> 6 & 63)])
        default:
            break
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The bytes of a strictly valid unpadded base64url text.
    /// - Throws: `StrictBase64URLError` for padding, a foreign character, an impossible length or non-zero
    ///   trailing bits.
    public static func decode(_ text: String) throws(StrictBase64URLError) -> [UInt8] {
        let input = Array(text.utf8)
        guard input.count % 4 != 1 else { throw .invalidLength(input.count) }
        var values: [UInt8] = []
        values.reserveCapacity(input.count)
        for (offset, byte) in input.enumerated() {
            guard let value = sextet(byte) else { throw .invalidCharacter(offset: offset) }
            values.append(value)
        }
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 3 / 4)
        var index = 0
        while index + 4 <= values.count {
            let chunk =
                UInt32(values[index]) << 18 | UInt32(values[index + 1]) << 12
                | UInt32(values[index + 2]) << 6 | UInt32(values[index + 3])
            out.append(UInt8(chunk >> 16 & 0xFF))
            out.append(UInt8(chunk >> 8 & 0xFF))
            out.append(UInt8(chunk & 0xFF))
            index += 4
        }
        switch values.count - index {
        case 2:
            guard values[index + 1] & 0x0F == 0 else { throw .nonZeroTrailingBits }
            out.append(values[index] << 2 | values[index + 1] >> 4)
        case 3:
            guard values[index + 2] & 0x03 == 0 else { throw .nonZeroTrailingBits }
            out.append(values[index] << 2 | values[index + 1] >> 4)
            out.append((values[index + 1] & 0x0F) << 4 | values[index + 2] >> 2)
        default:
            break
        }
        return out
    }

    static func sextet(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "-"): 62
        case UInt8(ascii: "_"): 63
        default: nil
        }
    }
}

/// Why a base64url text was refused.
public enum StrictBase64URLError: Error, Hashable, Sendable {
    case invalidLength(Int)
    case invalidCharacter(offset: Int)
    case nonZeroTrailingBits
}
