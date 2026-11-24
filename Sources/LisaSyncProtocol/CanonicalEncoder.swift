// The one canonical JSON encoding (plan §8.16.1) and its size derivation without allocation.

/// Encodes values in Lisa's canonical JSON form: UTF-8, object keys sorted by Unicode scalar value, no whitespace,
/// integers only, minimal escaping, no duplicate keys, nesting at most 16 deep.
///
/// Minimal escaping writes `\"` and `\\`, the short escapes `\b`, `\f`, `\n`, `\r` and `\t`, `\u00xx` in lowercase
/// hexadecimal for the other characters below U+0020, and every other character as its UTF-8 bytes.
public enum CanonicalEncoder {
    /// The canonical bytes of `value`.
    /// - Throws: `CanonicalError.tooDeep` or `.tooLarge` when `value` exceeds `limits`.
    public static func encode(_ value: CanonicalValue, limits: CanonicalLimits) throws(CanonicalError) -> [UInt8] {
        var sink = ByteSink()
        try write(value, depth: 0, limits: limits, into: &sink)
        guard sink.bytes.count <= limits.maxBytes else {
            throw .tooLarge(bytes: sink.bytes.count, limit: limits.maxBytes)
        }
        return sink.bytes
    }

    /// The length of the canonical encoding of `value`, computed without building it. Value-size rules use this
    /// to derive sizes from the encoded operation (plan §8.3.3).
    /// - Throws: `CanonicalError.tooDeep` when `value` nests more deeply than the canonical limit.
    public static func encodedLength(of value: CanonicalValue) throws(CanonicalError) -> Int {
        var sink = CountingSink()
        try write(value, depth: 0, limits: CanonicalLimits(maxBytes: .max), into: &sink)
        return sink.count
    }

    /// The length of the canonical encoding of `string` as a JSON string, quotes included.
    public static func encodedLength(ofString string: String) -> Int {
        var sink = CountingSink()
        writeString(string, into: &sink)
        return sink.count
    }

    // MARK: - Writing

    static func write(
        _ value: CanonicalValue, depth: Int, limits: CanonicalLimits, into sink: inout some CanonicalSink
    ) throws(CanonicalError) {
        switch value {
        case .null:
            sink.append(contentsOf: Literal.null)
        case .bool(let flag):
            sink.append(contentsOf: flag ? Literal.true : Literal.false)
        case .integer(let number):
            sink.append(contentsOf: Array(String(number).utf8))
        case .string(let string):
            writeString(string, into: &sink)
        case .array(let elements):
            guard depth + 1 <= limits.maxDepth else { throw .tooDeep(limit: limits.maxDepth, offset: sink.count) }
            sink.append(UInt8(ascii: "["))
            for (index, element) in elements.enumerated() {
                if index > 0 { sink.append(UInt8(ascii: ",")) }
                try write(element, depth: depth + 1, limits: limits, into: &sink)
            }
            sink.append(UInt8(ascii: "]"))
        case .object(let object):
            guard depth + 1 <= limits.maxDepth else { throw .tooDeep(limit: limits.maxDepth, offset: sink.count) }
            sink.append(UInt8(ascii: "{"))
            for (index, member) in object.members.enumerated() {
                if index > 0 { sink.append(UInt8(ascii: ",")) }
                writeString(member.key, into: &sink)
                sink.append(UInt8(ascii: ":"))
                try write(member.value, depth: depth + 1, limits: limits, into: &sink)
            }
            sink.append(UInt8(ascii: "}"))
        }
        if sink.count > limits.maxBytes { throw .tooLarge(bytes: sink.count, limit: limits.maxBytes) }
    }

    static func writeString(_ string: String, into sink: inout some CanonicalSink) {
        sink.append(UInt8(ascii: "\""))
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: sink.append(contentsOf: [0x5C, 0x22])
            case 0x5C: sink.append(contentsOf: [0x5C, 0x5C])
            case 0x08: sink.append(contentsOf: [0x5C, UInt8(ascii: "b")])
            case 0x0C: sink.append(contentsOf: [0x5C, UInt8(ascii: "f")])
            case 0x0A: sink.append(contentsOf: [0x5C, UInt8(ascii: "n")])
            case 0x0D: sink.append(contentsOf: [0x5C, UInt8(ascii: "r")])
            case 0x09: sink.append(contentsOf: [0x5C, UInt8(ascii: "t")])
            case 0x00..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                sink.append(contentsOf: [
                    0x5C, UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0"),
                    hex[Int(scalar.value >> 4)], hex[Int(scalar.value & 0xF)],
                ])
            default:
                appendUTF8(scalar.value, into: &sink)
            }
        }
        sink.append(UInt8(ascii: "\""))
    }

    /// Appends the UTF-8 encoding of one Unicode scalar value.
    static func appendUTF8(_ value: UInt32, into sink: inout some CanonicalSink) {
        switch value {
        case 0..<0x80:
            sink.append(UInt8(value))
        case 0x80..<0x800:
            sink.append(UInt8(0xC0 | (value >> 6)))
            sink.append(UInt8(0x80 | (value & 0x3F)))
        case 0x800..<0x10000:
            sink.append(UInt8(0xE0 | (value >> 12)))
            sink.append(UInt8(0x80 | ((value >> 6) & 0x3F)))
            sink.append(UInt8(0x80 | (value & 0x3F)))
        default:
            sink.append(UInt8(0xF0 | (value >> 18)))
            sink.append(UInt8(0x80 | ((value >> 12) & 0x3F)))
            sink.append(UInt8(0x80 | ((value >> 6) & 0x3F)))
            sink.append(UInt8(0x80 | (value & 0x3F)))
        }
    }

    enum Literal {
        static let null = Array("null".utf8)
        static let `true` = Array("true".utf8)
        static let `false` = Array("false".utf8)
    }
}

/// Where the encoder writes: real bytes, or only their count.
protocol CanonicalSink {
    var count: Int { get }
    mutating func append(_ byte: UInt8)
    mutating func append(contentsOf bytes: [UInt8])
}

struct ByteSink: CanonicalSink {
    var bytes: [UInt8] = []
    var count: Int { bytes.count }
    mutating func append(_ byte: UInt8) { bytes.append(byte) }
    mutating func append(contentsOf more: [UInt8]) { bytes.append(contentsOf: more) }
}

struct CountingSink: CanonicalSink {
    var count = 0
    mutating func append(_ byte: UInt8) { count += 1 }
    mutating func append(contentsOf more: [UInt8]) { count += more.count }
}
