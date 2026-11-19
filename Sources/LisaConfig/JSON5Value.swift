// The value tree a JSON5 document is read into, with the position of every value and key.

/// A 1-based line and column in a document, counted in Unicode scalars.
struct SourcePosition: Hashable, Comparable, Sendable {
    var line: Int
    var column: Int

    static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// A JSON5 number: its double value, plus the exact value of an integer literal that fits in `Int`.
struct JSON5Number: Hashable, Sendable {
    let doubleValue: Double
    /// Set for decimal integer literals (no point, no exponent) and hexadecimal literals that fit in `Int`.
    let integerValue: Int?

    /// The value as a whole number, when it is exactly one (`5`, `0x1F`, `5.0` or `1e3`).
    var exactInteger: Int? {
        if let integerValue { return integerValue }
        // Every integer up to 2^53 is exactly representable as a double.
        guard doubleValue.rounded() == doubleValue, abs(doubleValue) <= 9_007_199_254_740_992 else { return nil }
        return Int(doubleValue)
    }
}

/// A JSON5 value.
enum JSON5Value: Sendable {
    case null
    case bool(Bool)
    case number(JSON5Number)
    case string(String)
    case array([JSON5Node])
    case object(JSON5Object)
}

/// A value and the position where it starts.
struct JSON5Node: Sendable {
    let value: JSON5Value
    let position: SourcePosition
}

/// One member of an object: the key, where the key starts, and the value.
struct JSON5Member: Sendable {
    let key: String
    let keyPosition: SourcePosition
    let value: JSON5Node
}

/// An object with its members in document order. Keys are unique: the reader rejects duplicates.
struct JSON5Object: Sendable {
    let members: [JSON5Member]

    /// The member with `key`, if present.
    func member(_ key: String) -> JSON5Member? {
        members.first { $0.key == key }
    }
}
