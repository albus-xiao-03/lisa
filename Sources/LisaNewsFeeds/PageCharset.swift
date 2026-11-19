// Determines a page's character set (byte order mark, then Content-Type, then an HTML meta prescan) and decodes it;
// invalid UTF-8 becomes visible replacement characters, never silently different text.

import Foundation
import LisaHTTPSources
import LisaPorts

/// Character-set handling for retrieved pages.
enum PageCharset {
    /// How far into an HTML page a `<meta charset>` is looked for.
    static let prescanLength = 1_024

    /// The decoded text and the label of the character set used.
    static func decode(_ bytes: [UInt8], declared: String?, kind: PageKind) -> Result<
        (text: String, label: String), ConnectorError
    > {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .success((String(decoding: bytes.dropFirst(3), as: UTF8.self), "utf-8"))
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return decode(bytes, label: "utf-16", encoding: .utf16)
        }
        let label = declared ?? (kind == .html ? metaCharset(bytes) : nil) ?? "utf-8"
        guard let encoding = encoding(for: label) else {
            return .failure(
                ConnectorError(.unsupported, "the page uses the \(label) character set, which Lisa cannot read"))
        }
        if encoding == .utf8 {
            return .success((String(decoding: bytes, as: UTF8.self), "utf-8"))
        }
        return decode(bytes, label: label, encoding: encoding)
    }

    private static func decode(_ bytes: [UInt8], label: String, encoding: String.Encoding) -> Result<
        (text: String, label: String), ConnectorError
    > {
        guard let text = String(bytes: bytes, encoding: encoding) else {
            return .failure(ConnectorError(.parse, "the page is not valid \(label) text"))
        }
        return .success((text, label))
    }

    /// The Foundation encoding for a charset label. As browsers do, `us-ascii` and `iso-8859-1` labels are read as
    /// windows-1252, which pages so labeled commonly use.
    static func encoding(for label: String) -> String.Encoding? {
        switch label.lowercased() {
        case "utf-8", "utf8", "unicode-1-1-utf-8": .utf8
        case "us-ascii", "ascii", "iso-8859-1", "iso8859-1", "iso_8859-1", "latin1", "l1", "windows-1252", "cp1252",
            "x-cp1252":
            .windowsCP1252
        case "iso-8859-2", "iso8859-2", "latin2", "l2": .isoLatin2
        case "windows-1250", "cp1250": .windowsCP1250
        case "windows-1251", "cp1251": .windowsCP1251
        case "windows-1253", "cp1253": .windowsCP1253
        case "windows-1254", "cp1254": .windowsCP1254
        case "shift_jis", "shift-jis", "sjis", "x-sjis": .shiftJIS
        case "euc-jp": .japaneseEUC
        case "iso-2022-jp": .iso2022JP
        case "utf-16le": .utf16LittleEndian
        case "utf-16be": .utf16BigEndian
        case "utf-16": .utf16
        case "macintosh", "mac", "x-mac-roman": .macOSRoman
        default: nil
        }
    }

    /// The charset named by a `<meta charset>` or `<meta http-equiv="Content-Type">` near the start of the page.
    static func metaCharset(_ bytes: [UInt8]) -> String? {
        let head = String(decoding: bytes.prefix(prescanLength), as: UTF8.self).lowercased()
        var rest = head[...]
        while let tag = rest.range(of: "<meta") {
            let after = rest[tag.upperBound...]
            let end = after.firstIndex(of: ">") ?? after.endIndex
            if let label = charsetValue(in: after[..<end]) {
                // A UTF-16 label found by an ASCII-compatible scan cannot be right, so it means UTF-8.
                return label.hasPrefix("utf-16") ? "utf-8" : label
            }
            rest = after[end...]
        }
        return nil
    }

    /// The value after `charset=` in one tag's attributes, as in `charset="utf-8"` or
    /// `content="text/html; charset=iso-8859-1"`.
    private static func charsetValue(in attributes: Substring) -> String? {
        guard let name = attributes.range(of: "charset") else { return nil }
        let afterName = attributes[name.upperBound...].drop(while: { $0 == " " })
        guard afterName.first == "=" else { return nil }
        let value = afterName.dropFirst().drop(while: { $0 == " " || $0 == "\"" || $0 == "'" })
        let label = value.prefix { !" \"';/>\t\r\n".contains($0) }
        guard !label.isEmpty, label.utf8.count <= 40, label.utf8.allSatisfy(MediaType.isTokenByte) else { return nil }
        return String(label)
    }
}
