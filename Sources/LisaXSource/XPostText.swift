// Normalizes post text from X before it is stored: line endings, control characters and a byte limit.

/// Post text as Lisa stores it. The words are kept as X sent them; only characters that could disturb logs or terminals
/// are removed.
enum XPostText {
    /// The most bytes of one post's text kept. X's long posts reach 25,000 characters, which this allows.
    static let maxBytes = 131_072

    /// `text` with CR LF and CR turned into LF, other C0 and C1 control characters removed except tab, and at most
    /// `maxBytes` UTF-8 bytes, cut at a character boundary and marked with "…".
    static func normalized(_ text: String, maxBytes: Int = maxBytes) -> String {
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
        let cleaned = String(scalars)
        guard cleaned.utf8.count > maxBytes else { return cleaned }
        var kept = ""
        var used = 0
        let marker = "…"
        let budget = max(0, maxBytes - marker.utf8.count)
        for character in cleaned {
            let size = character.utf8.count
            guard used + size <= budget else { break }
            kept.append(character)
            used += size
        }
        return kept + marker
    }
}
