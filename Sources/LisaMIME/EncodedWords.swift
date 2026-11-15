// RFC 2047 encoded-word decoding for headers, and encoding of non-ASCII header text for outbound mail.

import Foundation

/// Encoded-word handling (`=?charset?B|Q?text?=`).
public enum EncodedWords {
    /// Decodes every encoded word in a header value. Whitespace between adjacent encoded words is removed.
    public static func decode(_ value: String) -> String {
        var result = ""
        var remaining = Substring(value)
        var lastWasEncoded = false
        while let start = remaining.range(of: "=?") {
            let before = remaining[..<start.lowerBound]
            let afterStart = remaining[start.upperBound...]
            guard let decoded = decodeWord(afterStart) else {
                result += before + "=?"
                remaining = afterStart
                lastWasEncoded = false
                continue
            }
            if !(lastWasEncoded && before.allSatisfy({ $0 == " " || $0 == "\t" })) {
                result += before
            }
            result += decoded.text
            remaining = afterStart[decoded.end...]
            lastWasEncoded = true
        }
        result += remaining
        return result
    }

    private static func decodeWord(_ text: Substring) -> (text: String, end: Substring.Index)? {
        let parts = text.split(separator: "?", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[3].hasPrefix("=") else { return nil }
        let charset = String(parts[0].split(separator: "*").first ?? parts[0])
        let mode = parts[1].uppercased()
        let payload = Data(parts[2].utf8)
        let bytes: Data
        switch mode {
        case "B": bytes = TransferDecoding.base64(payload)
        case "Q": bytes = TransferDecoding.quotedPrintable(payload, inHeader: true)
        default: return nil
        }
        let end = text.index(parts[3].startIndex, offsetBy: 1)
        return (CharsetDecoder.decode(bytes, charset: charset).text, end)
    }

    /// Encodes `text` as a single UTF-8 base64 encoded word when it contains non-ASCII characters.
    public static func encodeIfNeeded(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { return text }
        return "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }
}
