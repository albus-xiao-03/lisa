// The value model of Lisa's canonical JSON (plan §8.16.1): null, booleans, 64-bit integers, strings, arrays and
// objects. There are no floating-point numbers: instants are integer milliseconds and decimals travel as strings.

/// A JSON value in Lisa's canonical form.
///
/// Equality and hashing are byte-exact: two strings are equal only when their UTF-8 encodings are identical, so
/// canonically equivalent but differently encoded text (for example a precomposed and a decomposed "é") is never
/// mistaken for the same signed value.
public enum CanonicalValue: Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case string(String)
    case array([CanonicalValue])
    case object(CanonicalObject)
}

extension CanonicalValue: Hashable {
    public static func == (lhs: CanonicalValue, rhs: CanonicalValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            true
        case (.bool(let a), .bool(let b)):
            a == b
        case (.integer(let a), .integer(let b)):
            a == b
        case (.string(let a), .string(let b)):
            a.utf8.elementsEqual(b.utf8)
        case (.array(let a), .array(let b)):
            a == b
        case (.object(let a), .object(let b)):
            a == b
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0 as UInt8)
        case .bool(let value):
            hasher.combine(1 as UInt8)
            hasher.combine(value)
        case .integer(let value):
            hasher.combine(2 as UInt8)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(3 as UInt8)
            for byte in value.utf8 { hasher.combine(byte) }
        case .array(let values):
            hasher.combine(4 as UInt8)
            hasher.combine(values)
        case .object(let object):
            hasher.combine(5 as UInt8)
            hasher.combine(object)
        }
    }
}
