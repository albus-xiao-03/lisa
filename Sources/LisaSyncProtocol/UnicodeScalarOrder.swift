// Ordering and identity of canonical JSON object keys by Unicode scalar value (plan §8.16.1).

/// Compares strings by their sequences of Unicode scalar values, which is the order canonical JSON sorts object
/// keys in. Swift's own `String` comparison follows canonical equivalence instead, so it is not used here.
public enum UnicodeScalarOrder {
    /// Whether `lhs` sorts before `rhs` by Unicode scalar value.
    public static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        var left = lhs.unicodeScalars.makeIterator()
        var right = rhs.unicodeScalars.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil):
                return false
            case (nil, _):
                return true
            case (_, nil):
                return false
            case (let a?, let b?):
                if a.value != b.value { return a.value < b.value }
            }
        }
    }

    /// Whether two strings have exactly the same Unicode scalar sequence.
    public static func identical(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
    }
}
