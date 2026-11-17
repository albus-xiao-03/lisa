// The formats the Twilio call transport checks before building a request: Account and Call SIDs, and E.164 numbers.

/// Twilio identifier and phone-number formats, from the Call resource reference.
enum TwilioFormats {
    /// `^AC[0-9a-fA-F]{32}$`, the documented Account SID pattern. The SID becomes part of the request path, so
    /// nothing else is ever accepted.
    static func isAccountSID(_ text: String) -> Bool {
        hasSID(text, prefix: "AC")
    }

    /// `^CA[0-9a-fA-F]{32}$`, the documented Call SID pattern.
    static func isCallSID(_ text: String) -> Bool {
        hasSID(text, prefix: "CA")
    }

    /// E.164: `+` and 7 to 15 digits, the first not zero, with no spaces or punctuation.
    static func isE164(_ text: String) -> Bool {
        guard text.hasPrefix("+") else { return false }
        let digits = text.utf8.dropFirst()
        return (7...15).contains(digits.count) && digits.allSatisfy { (0x30...0x39).contains($0) }
            && digits.first != 0x30
    }

    /// Twilio-Request-Id values are quoted in results only when they are short and purely alphanumeric.
    static func isRequestID(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count)
            && text.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
            }
    }

    private static func hasSID(_ text: String, prefix: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == 34 && text.hasPrefix(prefix)
            && bytes.dropFirst(2).allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0)
            }
    }
}
