// Plain text for speech: the brief without markup, links or symbols that a speech synthesizer would read aloud.

import Foundation

/// Turns text into plain sentences for speech (SIRI-02: the brief is spoken). Markup is removed: Markdown emphasis,
/// headings, quotes and list bullets, link syntax (the label is kept), HTML tags and bare web addresses. Each line
/// becomes a sentence, so the synthesizer pauses between items.
public enum SpokenText {
    /// `text` as plain spoken sentences.
    public static func plain(_ text: String) -> String {
        var sentences: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = removingTags(removingLinkSyntax(String(rawLine)))
            line = removingLinePrefix(line)
            line = line.split(separator: " ").filter { !isWebAddress($0) }.joined(separator: " ")
            line = String(line.filter { !markupCharacters.contains($0) })
            line = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !line.isEmpty, line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            if let last = line.last, !sentenceEnds.contains(last) { line += "." }
            sentences.append(line)
        }
        return sentences.joined(separator: " ")
    }

    private static let markupCharacters: Set<Character> = ["*", "_", "`", "~", "#", "|"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", ":", ";", ","]
    private static let bulletPrefixes = ["- ", "* ", "+ ", "• ", "> "]

    /// `[label](address)` becomes `label`.
    private static func removingLinkSyntax(_ line: String) -> String {
        var result = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"), rest.index(after: close) < rest.endIndex,
                rest[rest.index(after: close)] == "(",
                let end = rest[close...].firstIndex(of: ")")
            else {
                result += rest[...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            result += rest[..<open]
            result += rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    /// Removes `<...>` tags.
    private static func removingTags(_ line: String) -> String {
        var result = ""
        var inTag = false
        for character in line {
            if character == "<" {
                inTag = true
            } else if character == ">", inTag {
                inTag = false
                result.append(" ")
            } else if !inTag {
                result.append(character)
            }
        }
        return result
    }

    /// Removes heading marks, quote marks and list bullets at the start of a line.
    private static func removingLinePrefix(_ line: String) -> String {
        var trimmed = line.drop { $0.isWhitespace }
        while trimmed.first == "#" { trimmed = trimmed.dropFirst() }
        for prefix in bulletPrefixes where trimmed.hasPrefix(prefix) {
            trimmed = trimmed.dropFirst(prefix.count)
            break
        }
        return String(trimmed)
    }

    /// Whether a word is a web address, which speech would spell out.
    private static func isWebAddress(_ word: Substring) -> Bool {
        let lowered = word.drop { "([{<\"'".contains($0) }.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("www.")
    }
}
