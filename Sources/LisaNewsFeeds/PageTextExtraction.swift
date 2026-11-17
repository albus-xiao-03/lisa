// Turns a decoded page into its title and visible text: HTML through LisaHTMLText (scripts, styles and embedded
// content removed, links never followed), plain text bounded as it is.

import Foundation
import LisaHTMLText

/// The readable parts of a page.
struct PageText: Hashable, Sendable {
    var title: String?
    var text: String
    var truncated: Bool
    var removedElements: Int
}

/// Text extraction for owner-initiated retrievals. Nothing the page refers to (images, scripts, styles, frames,
/// linked pages) is ever requested.
enum PageTextExtraction {
    /// How far into a page its `<title>` is looked for.
    static let titleSearchLength = 262_144
    static let maxTitleCharacters = 300

    static func extract(_ text: String, kind: PageKind, limit: Int) -> PageText {
        switch kind {
        case .plainText:
            let truncated = text.count > limit
            return PageText(
                title: nil, text: truncated ? String(text.prefix(limit)) + "…" : text, truncated: truncated,
                removedElements: 0)
        case .html:
            let result = HTMLText.convert(text, maxCharacters: limit)
            // HTMLText marks a cut with a trailing ellipsis, one character beyond the limit.
            return PageText(
                title: title(in: text), text: result.text, truncated: result.text.count > limit,
                removedElements: result.removedElements)
        }
    }

    /// The text of the first `<title>` element, with entities decoded and white space collapsed.
    static func title(in html: String) -> String? {
        let head = html.prefix(titleSearchLength)
        guard let open = head.range(of: "<title", options: .caseInsensitive),
            let openEnd = head[open.upperBound...].firstIndex(of: ">"),
            let close = head[openEnd...].range(of: "</title", options: .caseInsensitive)
        else { return nil }
        let inner = head[head.index(after: openEnd)..<close.lowerBound].prefix(4 * maxTitleCharacters)
        // The title is converted on its own, as paragraph text, so its entities are decoded like the body's.
        let converted = HTMLText.convert("<p>\(inner)</p>", maxCharacters: maxTitleCharacters).text
        let collapsed = converted.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
