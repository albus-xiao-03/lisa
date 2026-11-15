// Content-Transfer-Encoding decoding (base64, quoted-printable) and quoted-printable encoding for outbound mail.

import Foundation

/// Lenient transfer decoders: malformed input degrades to its literal bytes rather than being dropped.
public enum TransferDecoding {
    /// Decodes a body according to its Content-Transfer-Encoding.
    public static func decode(_ data: Data, encoding: String?) -> Data {
        switch encoding?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64": return base64(data)
        case "quoted-printable": return quotedPrintable(data, inHeader: false)
        default: return data
        }
    }

    /// Decodes base64, ignoring line breaks and invalid characters and tolerating missing padding.
    public static func base64(_ data: Data) -> Data {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        var cleaned = data.filter { alphabet.contains($0) }
        while cleaned.count % 4 != 0 { cleaned.append(UInt8(ascii: "=")) }
        return Data(base64Encoded: Data(cleaned)) ?? Data()
    }

    /// Decodes quoted-printable. In headers (RFC 2047 "Q"), underscores mean spaces.
    public static func quotedPrintable(_ data: Data, inHeader: Bool) -> Data {
        var output = Data()
        output.reserveCapacity(data.count)
        let bytes = [UInt8](data)
        var index = 0
        func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: byte - 48
            case 65...70: byte - 55
            case 97...102: byte - 87
            default: nil
            }
        }
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "=") {
                if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count, let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2])
                {
                    output.append(high << 4 | low)
                    index += 3
                    continue
                }
                output.append(byte)
            } else if inHeader, byte == UInt8(ascii: "_") {
                output.append(UInt8(ascii: " "))
            } else {
                output.append(byte)
            }
            index += 1
        }
        return output
    }

    /// Encodes text as quoted-printable with CRLF line breaks and lines of at most 76 characters.
    public static func encodeQuotedPrintable(_ text: String) -> String {
        var lines: [String] = []
        for sourceLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            var encoded = ""
            var current = ""
            let bytes = Array(sourceLine.utf8)
            for (offset, byte) in bytes.enumerated() {
                let isLast = offset == bytes.count - 1
                let needsEscape =
                    byte == UInt8(ascii: "=") || byte > 126 || (byte < 32 && byte != 9)
                    || (isLast && (byte == 32 || byte == 9))
                let piece = needsEscape ? String(format: "=%02X", byte) : String(UnicodeScalar(byte))
                if current.count + piece.count > 75 {
                    encoded += current + "=\r\n"
                    current = ""
                }
                current += piece
            }
            encoded += current
            lines.append(encoded)
        }
        return lines.joined(separator: "\r\n")
    }
}
