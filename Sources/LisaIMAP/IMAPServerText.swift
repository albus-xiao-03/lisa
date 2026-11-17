// Makes server-supplied response text safe to put in a failure summary: printable ASCII only, short, and withheld
// entirely if it contains the mailbox password.

import LisaRedaction

/// Server text is untrusted: it may carry control characters, unbounded length or, from a hostile server, the
/// credential it was sent. Summaries keep at most a short printable excerpt.
enum IMAPServerText {
    static let maxCharacters = 100

    /// A printable excerpt of `bytes`, or nil when there is nothing to show or it must be withheld.
    static func excerpt(_ bytes: [UInt8], withholdingIfContains secret: Sensitive<String>) -> String? {
        var printable = bytes.prefix(4 * maxCharacters).map { (0x20...0x7E).contains($0) ? $0 : 0x3F }[...]
        while printable.first == 0x20 { printable = printable.dropFirst() }
        while printable.last == 0x20 { printable = printable.dropLast() }
        let text = String(decoding: printable, as: UTF8.self)
        guard !text.isEmpty else { return nil }
        let password = secret.revealed
        if !password.isEmpty, String(decoding: bytes, as: UTF8.self).contains(password) || text.contains(password) {
            return nil
        }
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "…" : text
    }

    /// `summary`, followed by the response code and the server's excerpt when there is one.
    static func describe(
        _ summary: String, code: IMAPResponseCode?, text: [UInt8], withholdingIfContains secret: Sensitive<String>
    ) -> String {
        var parts = summary
        if let code { parts += " [\(code.name)]" }
        if let excerpt = excerpt(text, withholdingIfContains: secret) { parts += ": \(excerpt)" }
        return parts
    }
}
