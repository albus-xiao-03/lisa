// Rewrites undefined named entity references before parsing, so recovery never silently drops text.

import Foundation

/// XML defines only five named entities, and Lisa refuses DTD declarations, so any other `&name;` in a document is
/// undefined. libxml2's recovery mode drops such references together with the surrounding text. This pass, run before
/// parsing, rewrites them outside CDATA sections and comments:
/// - common HTML entity names become numeric character references;
/// - any other name becomes the literal text `&name;` (escaped as `&amp;name;`) so it stays visible.
enum EntityNormalizer {
    private static let predefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    private static let html: [String: UInt32] = [
        "nbsp": 160, "iexcl": 161, "cent": 162, "pound": 163, "curren": 164, "yen": 165, "brvbar": 166, "sect": 167,
        "uml": 168, "copy": 169, "ordf": 170, "laquo": 171, "not": 172, "shy": 173, "reg": 174, "macr": 175, "deg": 176,
        "plusmn": 177, "sup2": 178, "sup3": 179, "acute": 180, "micro": 181, "para": 182, "middot": 183, "cedil": 184,
        "sup1": 185, "ordm": 186, "raquo": 187, "frac14": 188, "frac12": 189, "frac34": 190, "iquest": 191,
        "agrave": 224, "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228, "aring": 229, "aelig": 230,
        "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234, "euml": 235, "igrave": 236, "iacute": 237,
        "icirc": 238, "iuml": 239, "ntilde": 241, "ograve": 242, "oacute": 243, "ocirc": 244, "otilde": 245,
        "ouml": 246, "oslash": 248, "ugrave": 249, "uacute": 250, "ucirc": 251, "uuml": 252, "szlig": 223,
        "times": 215, "divide": 247, "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218,
        "ldquo": 8220, "rdquo": 8221, "bdquo": 8222, "dagger": 8224, "bull": 8226, "hellip": 8230, "permil": 8240,
        "prime": 8242, "lsaquo": 8249, "rsaquo": 8250, "euro": 8364, "trade": 8482, "larr": 8592, "rarr": 8594,
        "uarr": 8593, "darr": 8595, "ensp": 8194, "emsp": 8195, "thinsp": 8201, "zwnj": 8204, "zwj": 8205,
    ]

    /// Returns the rewritten document and how many references were changed.
    static func normalize(_ data: Data) -> (Data, Int) {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + 64)
        var index = 0
        var changed = 0
        func starts(with marker: String, at position: Int) -> Bool {
            let markerBytes = Array(marker.utf8)
            return position + markerBytes.count <= bytes.count
                && Array(bytes[position..<position + markerBytes.count]) == markerBytes
        }
        func copy(until terminator: String) {
            let end = Array(terminator.utf8)
            while index < bytes.count {
                if starts(with: terminator, at: index) {
                    output.append(contentsOf: end)
                    index += end.count
                    return
                }
                output.append(bytes[index])
                index += 1
            }
        }
        while index < bytes.count {
            if starts(with: "<![CDATA[", at: index) {
                copy(until: "]]>")
                continue
            }
            if starts(with: "<!--", at: index) {
                copy(until: "-->")
                continue
            }
            let byte = bytes[index]
            guard byte == UInt8(ascii: "&") else {
                output.append(byte)
                index += 1
                continue
            }
            var end = index + 1
            while end < bytes.count, end - index <= 32,
                (bytes[end] >= 65 && bytes[end] <= 90) || (bytes[end] >= 97 && bytes[end] <= 122)
                    || (end > index + 1 && bytes[end] >= 48 && bytes[end] <= 57)
            {
                end += 1
            }
            guard end > index + 1, end < bytes.count, bytes[end] == UInt8(ascii: ";") else {
                output.append(byte)
                index += 1
                continue
            }
            let name = String(decoding: bytes[(index + 1)..<end], as: UTF8.self)
            if predefined.contains(name) {
                output.append(contentsOf: bytes[index...end])
            } else if let scalar = html[name.lowercased()] {
                output.append(contentsOf: Array("&#\(scalar);".utf8))
                changed += 1
            } else {
                output.append(contentsOf: Array("&amp;\(name);".utf8))
                changed += 1
            }
            index = end + 1
        }
        return (Data(output), changed)
    }
}
