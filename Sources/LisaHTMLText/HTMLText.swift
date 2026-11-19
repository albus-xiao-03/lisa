// Converts untrusted HTML to plain text: scripts, styles and embedded content dropped; links listed, never fetched.

import Foundation
import LisaXML

/// The text form of an HTML document.
public struct HTMLTextResult: Hashable, Sendable {
    public var text: String
    /// Link targets found in the document. Lisa never fetches them on its own.
    public var links: [String]
    /// How many active or embedded elements (scripts, frames, objects, images …) were removed.
    public var removedElements: Int
}

/// Sanitized HTML-to-text conversion (MAIL-01, SEC-02).
public enum HTMLText {
    private static let removed: Set<String> = [
        "script", "style", "head", "noscript", "template", "iframe", "frame", "frameset", "object", "embed", "applet",
        "svg", "math", "canvas", "video", "audio", "img", "picture", "source", "form", "button", "input", "select",
        "textarea", "link", "meta", "base",
    ]
    private static let blocks: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "blockquote", "pre", "table",
        "tr", "ul", "ol", "dl", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "address", "figure",
        "figcaption", "body", "html",
    ]

    /// Converts HTML to text. On a parsing failure the result is the visible tag-stripped text, never nothing.
    public static func convert(_ html: String, maxCharacters: Int = 200_000) -> HTMLTextResult {
        guard let root = try? SafeXMLReader.parseHTML(html) else {
            let stripped = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            return HTMLTextResult(text: collapse(stripped, limit: maxCharacters), links: [], removedElements: 0)
        }
        var state = State()
        state.walk(root)
        return HTMLTextResult(
            text: collapse(state.output, limit: maxCharacters), links: state.links, removedElements: state.removed)
    }

    private struct State {
        var output = ""
        var links: [String] = []
        var removed = 0

        mutating func walk(_ node: XMLNode) {
            switch node.kind {
            case .text:
                output += node.text
            case .element:
                let name = node.name.lowercased()
                if HTMLText.removed.contains(name) {
                    removed += 1
                    if name == "img", let alt = node.attributes["alt"], !alt.isEmpty { output += "[image: \(alt)]" }
                    return
                }
                switch name {
                case "br": output += "\n"
                case "li": output += "\n• "
                case "td", "th": output += " "
                default: break
                }
                if HTMLText.blocks.contains(name) { output += "\n" }
                for child in node.children { walk(child) }
                if name == "a", let href = node.attributes["href"], !href.isEmpty, links.count < 200 {
                    links.append(href)
                }
                if HTMLText.blocks.contains(name) { output += "\n" }
            }
        }
    }

    /// Collapses runs of spaces and blank lines and bounds the length. Line endings are normalized first: Swift treats
    /// `"\r\n"` as one character, so splitting on `"\n"` alone would leave CRLF lines joined.
    static func collapse(_ text: String, limit: Int) -> String {
        var lines: [String] = []
        var blank = false
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(
            of: "\r\n", with: "\n"
        )
        .replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).joined(separator: " ")
            if line.isEmpty {
                if !blank, !lines.isEmpty { lines.append("") }
                blank = true
            } else {
                lines.append(line)
                blank = false
            }
        }
        while lines.last == "" { lines.removeLast() }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)) + "…" : joined
    }
}
