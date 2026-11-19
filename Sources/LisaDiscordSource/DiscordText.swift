// Normalizes text from Discord before it is stored: line endings, control characters and byte limits.

import Foundation

/// Message text as Lisa stores it. The words are kept as Discord sent them; only characters that could disturb logs or
/// terminals are removed.
enum DiscordText {
    /// `text` with CR LF and CR turned into LF, other C0 and C1 control characters removed except tab, and at most
    /// `maxBytes` UTF-8 bytes, cut at a character boundary and marked with "…".
    static func normalized(_ text: String, maxBytes: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            defer { previousWasCR = scalar == "\r" }
            switch scalar.value {
            case 0x0D:
                scalars.append("\n")
            case 0x0A:
                if !previousWasCR { scalars.append("\n") }
            case 0x09:
                scalars.append(scalar)
            case 0x00...0x1F, 0x7F...0x9F:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return truncated(String(scalars), maxBytes: maxBytes)
    }

    /// One line of at most `maxBytes`: line breaks and tabs become spaces.
    static func singleLine(_ text: String, maxBytes: Int) -> String {
        let flattened = normalized(text, maxBytes: .max).map { $0 == "\n" || $0 == "\t" ? " " : $0 }
        return truncated(String(flattened).trimmingCharacters(in: .whitespaces), maxBytes: maxBytes)
    }

    private static func truncated(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        let marker = "…"
        let budget = max(0, maxBytes - marker.utf8.count)
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            guard used + size <= budget else { break }
            kept.append(character)
            used += size
        }
        return kept + marker
    }
}
