// The TwiML a call follows: one <Say> verb speaking the message text, XML-escaped, free of characters XML forbids, and
// within Twilio's documented length limits.

/// Builds the inline TwiML for a call. The call never carries a `Url`, so Twilio fetches no instructions from anywhere.
enum TwiMLSpeech {
    /// `<Say>` accepts 4,000 characters with basic voices but 3,000 with Amazon Polly voices. The account's default
    /// voice is not known here, so the stricter limit applies, counted in UTF-8 bytes (never fewer than characters).
    static let maxSpokenBytes = 3_000
    /// The `Twiml` parameter is limited to 4,000 characters, also counted in UTF-8 bytes.
    static let maxDocumentBytes = 4_000
    /// Text beyond this many characters can never fit, so longer input is cut first.
    static let maxInputCharacters = 16_384

    /// The TwiML document that speaks `text`, or `nil` when nothing speakable remains.
    static func document(speaking text: String) -> String? {
        let spoken = speakable(text)
        return spoken.isEmpty ? nil : wrap(escaped(spoken))
    }

    /// `text` on one line, without control characters, and shortened at a word boundary when the limits require it.
    static func speakable(_ text: String) -> String {
        let line = singleLine(text)
        if fits(line) { return line }
        let characters = Array(line)
        // Longer prefixes are never shorter in bytes or once escaped, so a binary search finds the longest that fits.
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(String(characters[0..<middle])) { low = middle } else { high = middle - 1 }
        }
        var prefix = characters[0..<low]
        if low < characters.count, characters[low] != " ", let space = prefix.lastIndex(of: " "), space > 0 {
            prefix = characters[0..<space]
        }
        while prefix.last == " " { prefix = prefix.dropLast() }
        return String(prefix)
    }

    static func fits(_ text: String) -> Bool {
        text.utf8.count <= maxSpokenBytes && wrap(escaped(text)).utf8.count <= maxDocumentBytes
    }

    static func wrap(_ escapedText: String) -> String {
        "<Response><Say>\(escapedText)</Say></Response>"
    }

    /// XML character data with markup characters as entity references, so the text can never add TwiML or SSML.
    static func escaped(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result.append(contentsOf: "&amp;".unicodeScalars)
            case "<": result.append(contentsOf: "&lt;".unicodeScalars)
            case ">": result.append(contentsOf: "&gt;".unicodeScalars)
            case "\"": result.append(contentsOf: "&quot;".unicodeScalars)
            case "'": result.append(contentsOf: "&apos;".unicodeScalars)
            default: result.append(scalar)
            }
        }
        return String(result)
    }

    /// Whitespace, control characters (which include every C0 character XML 1.0 forbids) and noncharacters such as
    /// U+FFFE and U+FFFF become single spaces, and the ends are trimmed.
    static func singleLine(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.prefix(maxInputCharacters).unicodeScalars {
            let properties = scalar.properties
            if properties.isWhitespace || properties.generalCategory == .control || properties.isNoncharacterCodePoint
                || properties.generalCategory == .lineSeparator || properties.generalCategory == .paragraphSeparator
            {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace { result.append(" ") }
            pendingSpace = false
            result.append(scalar)
        }
        return String(result)
    }
}
