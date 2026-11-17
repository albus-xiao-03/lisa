// X post and user identifiers: 1 to 19 ASCII digits, validated and compared as 64-bit numbers.

/// Numeric X identifiers. The X API v2 specification (version 2.174) gives user and post IDs the pattern
/// `^[0-9]{1,19}$`, so every valid identifier fits in a `UInt64` and identifiers order numerically, newest highest.
enum XIdentifier {
    /// Whether `text` is 1 to 19 ASCII digits.
    static func isValid(_ text: String) -> Bool {
        value(text) != nil
    }

    /// The numeric value, or nil when `text` is not a valid identifier.
    static func value(_ text: String) -> UInt64? {
        guard (1...19).contains(text.utf8.count), text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return UInt64(text)
    }

    /// The numerically largest valid identifier among `candidates`, ignoring nil and invalid values.
    static func largest(_ candidates: [String?]) -> String? {
        var best: (text: String, value: UInt64)?
        for case let text? in candidates {
            guard let number = value(text) else { continue }
            if best == nil || number > best!.value { best = (text, number) }
        }
        return best?.text
    }

    /// Whether `first` is numerically greater than `second`; false when either is invalid.
    static func isGreater(_ first: String, than second: String) -> Bool {
        guard let a = value(first), let b = value(second) else { return false }
        return a > b
    }
}
