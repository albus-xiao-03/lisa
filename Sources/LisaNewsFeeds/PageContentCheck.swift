// Decides whether a retrieved body is a readable page: HTML, XHTML or plain text, never other media.

import LisaHTTPSources
import LisaPorts

/// How a page's text is read.
enum PageKind: Hashable, Sendable {
    case html
    case plainText

    var mediaType: String {
        switch self {
        case .html: "text/html"
        case .plainText: "text/plain"
        }
    }
}

/// Media acceptance for owner-initiated retrievals. Documents, images and other media are not analyzed in R1, so
/// they are refused with a reason instead of being read as text.
enum PageContentCheck {
    /// How much of an unlabeled body is examined.
    static let sniffLength = 1_024

    static func kind(of bytes: [UInt8], mediaType: MediaType?) -> Result<PageKind, ConnectorError> {
        guard bytes.contains(where: { !isSpace($0) }) else {
            return .failure(ConnectorError(.parse, "the page is empty"))
        }
        if let mediaType {
            switch mediaType.essence {
            case "text/html", "application/xhtml+xml": return .success(.html)
            case "text/plain": return .success(.plainText)
            default:
                return .failure(
                    ConnectorError(
                        .unsupported,
                        "the link serves \(mediaType.essence), not a web page; Lisa reads only HTML and plain-text"
                            + " pages"))
            }
        }
        let head = bytes.prefix(sniffLength)
        // NUL bytes mean binary content, unless the page is UTF-16 text with a byte order mark.
        let utf16 = bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
        if !utf16, head.contains(0) {
            return .failure(ConnectorError(.unsupported, "the link serves binary content, not a web page"))
        }
        let first = head.drop(while: { isSpace($0) || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF }).first
        return .success(first == UInt8(ascii: "<") || utf16 ? .html : .plainText)
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
