// The strict, bounded decoder for canonical JSON (plan §8.16.1, §8.2.1).

/// Decodes canonical JSON and accepts nothing else.
///
/// The input must be valid UTF-8 within the size limit, contain no whitespace, nest at most `maxDepth` containers,
/// use integers only, and repeat no object key, exactly or as canonically equivalent text. Finally the decoded value
/// is encoded again and must reproduce the input byte for byte, so any non-canonical spelling (unsorted keys, an
/// unnecessary escape, uppercase hexadecimal, a leading zero, negative zero) is refused.
public enum CanonicalDecoder {
    /// Decodes `bytes` as one canonical JSON value.
    public static func decode(_ bytes: [UInt8], limits: CanonicalLimits) throws(CanonicalError) -> CanonicalValue {
        guard bytes.count <= limits.maxBytes else { throw .tooLarge(bytes: bytes.count, limit: limits.maxBytes) }
        var parser = CanonicalParser(bytes: bytes, maxDepth: limits.maxDepth)
        let value = try parser.parseValue(depth: 0)
        guard parser.index == bytes.count else { throw .trailingBytes(offset: parser.index) }
        let canonical = try CanonicalEncoder.encode(value, limits: limits)
        guard canonical == bytes else {
            let offset =
                zip(canonical, bytes).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                ?? min(canonical.count, bytes.count)
            throw .nonCanonical(offset: offset)
        }
        return value
    }
}

/// A recursive-descent parser over a byte array. Recursion is bounded by the nesting limit (at most 16).
struct CanonicalParser {
    let bytes: [UInt8]
    let maxDepth: Int
    var index = 0

    init(bytes: [UInt8], maxDepth: Int) {
        self.bytes = bytes
        self.maxDepth = maxDepth
    }

    mutating func parseValue(depth: Int) throws(CanonicalError) -> CanonicalValue {
        guard index < bytes.count else { throw .unexpectedEnd }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            return .object(try parseObject(depth: depth + 1))
        case UInt8(ascii: "["):
            return .array(try parseArray(depth: depth + 1))
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try expect(CanonicalEncoder.Literal.true)
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect(CanonicalEncoder.Literal.false)
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect(CanonicalEncoder.Literal.null)
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .integer(try parseInteger())
        case let byte:
            throw .unexpectedByte(byte, offset: index)
        }
    }

    mutating func expect(_ literal: [UInt8]) throws(CanonicalError) {
        for expected in literal {
            guard index < bytes.count else { throw .unexpectedEnd }
            guard bytes[index] == expected else { throw .unexpectedByte(bytes[index], offset: index) }
            index += 1
        }
    }

    mutating func take(_ expected: UInt8) throws(CanonicalError) {
        guard index < bytes.count else { throw .unexpectedEnd }
        guard bytes[index] == expected else { throw .unexpectedByte(bytes[index], offset: index) }
        index += 1
    }

    mutating func parseObject(depth: Int) throws(CanonicalError) -> CanonicalObject {
        guard depth <= maxDepth else { throw .tooDeep(limit: maxDepth, offset: index) }
        try take(UInt8(ascii: "{"))
        var members: [CanonicalObject.Member] = []
        var seen = Set<String>()
        guard index < bytes.count else { throw .unexpectedEnd }
        if bytes[index] == UInt8(ascii: "}") {
            index += 1
            return CanonicalObject(sortedUniqueMembers: members)
        }
        while true {
            let keyOffset = index
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                guard index < bytes.count else { throw .unexpectedEnd }
                throw .unexpectedByte(bytes[index], offset: index)
            }
            let key = try parseString()
            guard seen.insert(key).inserted else { throw .duplicateKey(key) }
            if let previous = members.last?.key, !UnicodeScalarOrder.precedes(previous, key) {
                throw .nonCanonical(offset: keyOffset)
            }
            try take(UInt8(ascii: ":"))
            let value = try parseValue(depth: depth)
            members.append(CanonicalObject.Member(key: key, value: value))
            guard index < bytes.count else { throw .unexpectedEnd }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try take(UInt8(ascii: "}"))
            return CanonicalObject(sortedUniqueMembers: members)
        }
    }

    mutating func parseArray(depth: Int) throws(CanonicalError) -> [CanonicalValue] {
        guard depth <= maxDepth else { throw .tooDeep(limit: maxDepth, offset: index) }
        try take(UInt8(ascii: "["))
        var elements: [CanonicalValue] = []
        guard index < bytes.count else { throw .unexpectedEnd }
        if bytes[index] == UInt8(ascii: "]") {
            index += 1
            return elements
        }
        while true {
            elements.append(try parseValue(depth: depth))
            guard index < bytes.count else { throw .unexpectedEnd }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try take(UInt8(ascii: "]"))
            return elements
        }
    }

    mutating func parseInteger() throws(CanonicalError) -> Int64 {
        let start = index
        var negative = false
        if bytes[index] == UInt8(ascii: "-") {
            negative = true
            index += 1
        }
        guard index < bytes.count else { throw .unexpectedEnd }
        guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else {
            throw .unexpectedByte(bytes[index], offset: index)
        }
        var magnitude: UInt64 = 0
        let limit: UInt64 = negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        var digits = 0
        while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
            let digit = UInt64(bytes[index] - UInt8(ascii: "0"))
            let (times10, overflow1) = magnitude.multipliedReportingOverflow(by: 10)
            let (sum, overflow2) = times10.addingReportingOverflow(digit)
            guard !overflow1, !overflow2, sum <= limit else { throw .integerOutOfRange(offset: start) }
            magnitude = sum
            digits += 1
            index += 1
        }
        if index < bytes.count,
            [UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")].contains(bytes[index])
        {
            throw .nonInteger(offset: start)
        }
        // A leading zero ("01") or negative zero ("-0") is valid JSON but not canonical.
        let firstDigit = bytes[negative ? start + 1 : start]
        if firstDigit == UInt8(ascii: "0"), digits > 1 || negative { throw .nonCanonical(offset: start) }
        if negative {
            return magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude)
        }
        return Int64(magnitude)
    }

    mutating func parseString() throws(CanonicalError) -> String {
        try take(UInt8(ascii: "\""))
        var scalars = String.UnicodeScalarView()
        while true {
            guard index < bytes.count else { throw .unexpectedEnd }
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return String(scalars)
            case UInt8(ascii: "\\"):
                scalars.append(try parseEscape())
            case 0x00..<0x20:
                throw .controlCharacter(offset: index)
            case 0x20..<0x80:
                scalars.append(Unicode.Scalar(byte))
                index += 1
            default:
                scalars.append(try parseUTF8Scalar())
            }
        }
    }

    mutating func parseEscape() throws(CanonicalError) -> Unicode.Scalar {
        let start = index
        index += 1
        guard index < bytes.count else { throw .unexpectedEnd }
        let code = bytes[index]
        index += 1
        switch code {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{08}"
        case UInt8(ascii: "f"): return "\u{0C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"):
            let first = try parseHex4(escapeStart: start)
            switch first {
            case 0xD800...0xDBFF:
                guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                    bytes[index + 1] == UInt8(ascii: "u")
                else { throw .invalidEscape(offset: start) }
                index += 2
                let second = try parseHex4(escapeStart: start)
                guard (0xDC00...0xDFFF).contains(second) else { throw .invalidEscape(offset: start) }
                let value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                guard let scalar = Unicode.Scalar(value) else { throw .invalidEscape(offset: start) }
                return scalar
            case 0xDC00...0xDFFF:
                throw .invalidEscape(offset: start)
            default:
                guard let scalar = Unicode.Scalar(first) else { throw .invalidEscape(offset: start) }
                return scalar
            }
        default:
            throw .invalidEscape(offset: start)
        }
    }

    mutating func parseHex4(escapeStart: Int) throws(CanonicalError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw .unexpectedEnd }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw .invalidEscape(offset: escapeStart)
            }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    /// Decodes one multi-byte UTF-8 sequence (RFC 3629): no overlong forms, no surrogates, nothing above U+10FFFF.
    mutating func parseUTF8Scalar() throws(CanonicalError) -> Unicode.Scalar {
        let start = index
        let lead = bytes[index]
        let length: Int
        var value: UInt32
        var lowerBound: UInt8 = 0x80
        var upperBound: UInt8 = 0xBF
        switch lead {
        case 0xC2...0xDF:
            length = 2
            value = UInt32(lead & 0x1F)
        case 0xE0:
            length = 3
            value = UInt32(lead & 0x0F)
            lowerBound = 0xA0
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            value = UInt32(lead & 0x0F)
        case 0xED:
            length = 3
            value = UInt32(lead & 0x0F)
            upperBound = 0x9F
        case 0xF0:
            length = 4
            value = UInt32(lead & 0x07)
            lowerBound = 0x90
        case 0xF1...0xF3:
            length = 4
            value = UInt32(lead & 0x07)
        case 0xF4:
            length = 4
            value = UInt32(lead & 0x07)
            upperBound = 0x8F
        default:
            throw .invalidUTF8(offset: start)
        }
        guard index + length <= bytes.count else { throw .invalidUTF8(offset: start) }
        for position in 1..<length {
            let continuation = bytes[index + position]
            let low: UInt8 = position == 1 ? lowerBound : 0x80
            let high: UInt8 = position == 1 ? upperBound : 0xBF
            guard (low...high).contains(continuation) else { throw .invalidUTF8(offset: start) }
            value = value << 6 | UInt32(continuation & 0x3F)
        }
        index += length
        guard let scalar = Unicode.Scalar(value) else { throw .invalidUTF8(offset: start) }
        return scalar
    }
}
