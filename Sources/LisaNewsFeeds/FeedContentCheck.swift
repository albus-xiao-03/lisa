// Checks that a downloaded body looks like a whole RSS or Atom document before news ingestion reads it: not empty,
// not a web page or JSON, an XML root of rss, feed or RDF, and its closing tag present.

import Foundation
import LisaHTTPSources
import LisaPorts

/// Content sniffing for news feeds. The feed parser makes the final decision; this check gives the owner a precise
/// reason for the common failures (a home page instead of a feed, a login page, a JSON Feed, a cut-off download).
enum FeedContentCheck {
    /// How much of the start and of the end of a document is examined.
    static let scanLimit = 65_536

    /// Nil when `body` can be handed to news ingestion; otherwise the classified reason.
    static func error(in body: Data, mediaType: MediaType?) -> ConnectorError? {
        let bytes = [UInt8](body)
        guard !bytes.allSatisfy(isSpace) else {
            return ConnectorError(.parse, "the server returned an empty document instead of a feed")
        }
        if bytes.starts(with: [0, 0, 0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE, 0, 0]) {
            return ConnectorError(.unsupported, "the feed is UTF-32 text, which Lisa does not read")
        }
        let prefix: String
        let asciiCompatible: Bool
        if let text = utf16Prefix(bytes) {
            prefix = text
            asciiCompatible = false
        } else {
            let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            prefix = String(decoding: bytes[start..<min(bytes.count, start + scanLimit)], as: UTF8.self)
            asciiCompatible = true
        }
        let trimmed = prefix.drop(while: \.isWhitespace)
        switch trimmed.first {
        case "{", "[":
            return ConnectorError(
                .unsupported,
                "the address serves JSON (perhaps a JSON Feed), which Lisa does not read; use the site's RSS or Atom"
                    + " feed")
        case "<":
            break
        default:
            return ConnectorError(.parse, "the server returned data that is not an RSS or Atom feed")
        }
        switch rootElement(in: trimmed) {
        case .unknown:
            return nil
        case .notWellFormed:
            return ConnectorError(.parse, "the server returned data that is not an RSS or Atom feed")
        case .webPage:
            return webPage
        case .element(let name, let selfClosing):
            switch name.split(separator: ":").last.map({ $0.lowercased() }) {
            case "rss", "feed", "rdf":
                break
            case "html":
                return webPage
            default:
                return ConnectorError(
                    .parse, "the document is XML, but its root element <\(safeName(name))> is not an RSS or Atom feed")
            }
            if asciiCompatible, !selfClosing, !hasClosingTag(name, in: bytes) {
                return ConnectorError(
                    .partial,
                    "the feed ends before its closing </\(safeName(name))> tag; the download may have been cut short")
            }
            return nil
        }
    }

    private static let webPage = ConnectorError(
        .parse,
        "the server returned a web page instead of a feed; the address may be the site's home page rather than its feed,"
            + " or a page asking to sign in")

    private enum Root {
        case element(String, selfClosing: Bool)
        case webPage
        case notWellFormed
        /// Not found within the scanned prefix; the parser decides.
        case unknown
    }

    /// The first element after the prolog (XML declaration, processing instructions, comments, document type).
    private static func rootElement(in text: Substring) -> Root {
        var rest = text
        while true {
            rest = rest.drop(while: \.isWhitespace)
            if rest.isEmpty { return .unknown }
            if rest.hasPrefix("<?") {
                guard let end = rest.range(of: "?>") else { return .unknown }
                rest = rest[end.upperBound...]
            } else if rest.hasPrefix("<!--") {
                guard let end = rest.range(of: "-->") else { return .unknown }
                rest = rest[end.upperBound...]
            } else if rest.prefix(9).uppercased() == "<!DOCTYPE" {
                let name = rest.dropFirst(9).drop(while: \.isWhitespace).prefix {
                    !$0.isWhitespace && $0 != ">" && $0 != "["
                }
                if name.lowercased() == "html" { return .webPage }
                guard let end = doctypeEnd(rest) else { return .unknown }
                rest = rest[end...]
            } else if rest.hasPrefix("<") {
                let name = rest.dropFirst().prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
                guard !name.isEmpty else { return .notWellFormed }
                let afterName = rest.dropFirst(1 + name.count)
                var selfClosing = false
                if let close = afterName.firstIndex(of: ">"), close > afterName.startIndex {
                    selfClosing = afterName[afterName.index(before: close)] == "/"
                }
                return .element(String(name), selfClosing: selfClosing)
            } else {
                return .notWellFormed
            }
        }
    }

    /// The index after a document type declaration, including an internal subset in brackets.
    private static func doctypeEnd(_ text: Substring) -> Substring.Index? {
        guard let stop = text.firstIndex(where: { $0 == ">" || $0 == "[" }) else { return nil }
        if text[stop] == ">" { return text.index(after: stop) }
        guard let close = text[stop...].firstIndex(of: "]"), let end = text[close...].firstIndex(of: ">") else {
            return nil
        }
        return text.index(after: end)
    }

    /// Whether `</name>` (white space allowed before `>`) occurs near the end; trailing comments are allowed after it.
    private static func hasClosingTag(_ name: String, in bytes: [UInt8]) -> Bool {
        let marker = Array("</\(name)".utf8)
        let lowest = max(0, bytes.count - scanLimit)
        var index = bytes.count - marker.count
        while index >= lowest {
            if bytes[index] == marker[0], bytes[index..<index + marker.count].elementsEqual(marker) {
                var after = index + marker.count
                while after < bytes.count, isSpace(bytes[after]) { after += 1 }
                if after < bytes.count, bytes[after] == UInt8(ascii: ">") { return true }
            }
            index -= 1
        }
        return false
    }

    /// A UTF-16 document's first characters, from its byte order mark or, without one, from `<?` (XML 1.0
    /// Appendix F); nil for other documents.
    private static func utf16Prefix(_ bytes: [UInt8]) -> String? {
        let bigEndian: Bool
        let start: Int
        if bytes.starts(with: [0xFE, 0xFF]) {
            (bigEndian, start) = (true, 2)
        } else if bytes.starts(with: [0xFF, 0xFE]) {
            (bigEndian, start) = (false, 2)
        } else if bytes.starts(with: [0x00, 0x3C, 0x00, 0x3F]) {
            (bigEndian, start) = (true, 0)
        } else if bytes.starts(with: [0x3C, 0x00, 0x3F, 0x00]) {
            (bigEndian, start) = (false, 0)
        } else {
            return nil
        }
        let end = start + (min(bytes.count - start, scanLimit) / 2) * 2
        let units = stride(from: start, to: end, by: 2).map { index in
            bigEndian
                ? UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                : UInt16(bytes[index + 1]) << 8 | UInt16(bytes[index])
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// An element name fit for a summary.
    private static func safeName(_ name: String) -> String {
        guard name.utf8.count <= 40 else { return "unrecognized" }
        let allowed = name.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || ":_-.".utf8.contains(byte)
        }
        return allowed ? name : "unrecognized"
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
