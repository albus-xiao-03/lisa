// One complete IMAP server response as the framer delivers it: the response text with literal data set aside.

import Foundation

/// A complete server response: one logical line whose literals (`{n}` CRLF followed by n octets) were read
/// separately (RFC 9051 §4.3).
struct IMAPRawResponse: Hashable, Sendable {
    /// The response text without its final CRLF. Each literal keeps its `{n}` marker; the CRLF after the marker
    /// and the literal octets are not part of the text.
    var text: [UInt8]
    /// The literal octets, in order of appearance.
    var literals: [Data]
    /// For each literal, the offset in `text` just after its closing `}`.
    var literalEnds: [Int]

    init(text: [UInt8], literals: [Data] = [], literalEnds: [Int] = []) {
        self.text = text
        self.literals = literals
        self.literalEnds = literalEnds
    }
}
