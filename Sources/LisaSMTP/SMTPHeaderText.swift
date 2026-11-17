// Subject and display-name text for outgoing mail: kept on one line without control characters, and shortened when
// needed so that LisaMIME's encoding of it stays within the line limits of RFC 5322 §2.1.1 and RFC 2047 §2.

import LisaMIME

/// Prepares header text before LisaMIME composes it. LisaMIME encodes a non-ASCII value as a single encoded word and
/// does not fold lines, so the text is shortened, with an ellipsis, until its header line fits.
enum SMTPHeaderText {
    /// RFC 5322 §2.1.1: a line MUST be no more than 998 characters, excluding CRLF.
    static let maxLineLength = 998
    /// RFC 2047 §2: a header line that contains an encoded word is limited to 76 characters.
    static let maxEncodedLineLength = 76
    /// Text beyond this many characters can never fit on a header line, so longer input is cut first.
    static let maxInputCharacters = 8_192
    static let ellipsis = "..."

    /// `text` on one line: line breaks, tabs, other whitespace and control characters become single spaces, and the
    /// ends are trimmed.
    static func singleLine(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.prefix(maxInputCharacters).unicodeScalars {
            let category = scalar.properties.generalCategory
            if scalar.properties.isWhitespace || category == .control || category == .lineSeparator
                || category == .paragraphSeparator
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

    /// The subject to give LisaMIME: one line, shortened so that `Subject: <encoded subject>` fits.
    static func subject(_ text: String) -> String {
        let line = singleLine(text)
        return fitted(line) { candidate in
            let encoded = EncodedWords.encodeIfNeeded(candidate)
            return fits(lineLength: "Subject: ".utf8.count + encoded.utf8.count, encoded: encoded != candidate)
        } ?? ""
    }

    /// The display name to give LisaMIME for `address`, or `nil` when there is none or none fits. Quotes and
    /// backslashes are removed, because LisaMIME quotes ASCII names without escaping them.
    static func displayName(_ name: String?, address: String) -> String? {
        guard let name else { return nil }
        let cleaned = singleLine(String(name.prefix(maxInputCharacters).filter { $0 != "\"" && $0 != "\\" }))
        let surroundings = "From: ".utf8.count + " <".utf8.count + address.utf8.count + ">".utf8.count
        return fitted(cleaned) { candidate in
            let encoded = EncodedWords.encodeIfNeeded(candidate)
            let isEncoded = encoded != candidate
            let formatted = isEncoded ? encoded.utf8.count : candidate.utf8.count + 2
            return fits(lineLength: surroundings + formatted, encoded: isEncoded)
        }
    }

    static func fits(lineLength: Int, encoded: Bool) -> Bool {
        lineLength <= (encoded ? maxEncodedLineLength : maxLineLength)
    }

    /// `text` when `accepts` it; otherwise its longest prefix, cut between characters (never inside a multi-byte
    /// character, as RFC 2047 §5 requires) and followed by an ellipsis, that `accepts` takes. `nil` when nothing fits.
    static func fitted(_ text: String, accepts: (String) -> Bool) -> String? {
        guard !text.isEmpty else { return nil }
        let characters = Array(text.prefix(maxInputCharacters))
        if characters.count == text.count, accepts(text) { return text }
        func candidate(_ count: Int) -> String {
            var prefix = String(characters[0..<count])
            while prefix.last == " " { prefix.removeLast() }
            return prefix + ellipsis
        }
        // Longer prefixes never encode shorter, and once a prefix needs encoding every longer one does, so the
        // prefixes that fit are exactly the shortest ones: a binary search finds the longest.
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if accepts(candidate(middle)) { low = middle } else { high = middle - 1 }
        }
        return low == 0 ? nil : candidate(low)
    }
}
