// Decodes text in a named charset: Foundation for its supported set, iconv for the rest, a visible marker otherwise.

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The result of decoding text in a declared charset.
public struct DecodedText: Hashable, Sendable {
    public var text: String
    /// False when the charset was unknown or the bytes were invalid; `text` then holds a visible marker or a
    /// best-effort reading clearly labeled as such.
    public var faithful: Bool
}

/// Converts bytes in a declared charset to text.
public enum CharsetDecoder {
    private static let foundationEncodings: [String: String.Encoding] = [
        "utf-8": .utf8, "utf8": .utf8, "us-ascii": .ascii, "ascii": .ascii, "ansi_x3.4-1968": .ascii,
        "iso-8859-1": .isoLatin1, "iso8859-1": .isoLatin1, "latin1": .isoLatin1, "iso-8859-2": .isoLatin2,
        "windows-1250": .windowsCP1250, "windows-1251": .windowsCP1251, "windows-1252": .windowsCP1252,
        "cp1252": .windowsCP1252, "windows-1253": .windowsCP1253, "windows-1254": .windowsCP1254,
        "utf-16": .utf16, "utf-16le": .utf16LittleEndian, "utf-16be": .utf16BigEndian, "shift_jis": .shiftJIS,
        "shift-jis": .shiftJIS, "sjis": .shiftJIS, "iso-2022-jp": .iso2022JP,
    ]

    /// Charsets handed to iconv when Foundation does not support them on every platform.
    private static let iconvCharsets: Set<String> = [
        "euc-jp", "gbk", "gb2312", "gb18030", "big5", "big5-hkscs", "euc-kr", "ks_c_5601-1987", "koi8-r", "koi8-u",
        "iso-8859-3", "iso-8859-4", "iso-8859-5", "iso-8859-6", "iso-8859-7", "iso-8859-8", "iso-8859-9",
        "iso-8859-10", "iso-8859-13", "iso-8859-14", "iso-8859-15", "iso-8859-16", "windows-1255", "windows-1256",
        "windows-1257", "windows-1258", "windows-874", "tis-620", "cp866", "macintosh",
    ]

    /// Decodes `data` declared as `charset` (UTF-8 when no charset is declared).
    public static func decode(_ data: Data, charset: String?) -> DecodedText {
        let name = (charset ?? "utf-8").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let encoding = foundationEncodings[name], let text = String(data: data, encoding: encoding) {
            return DecodedText(text: text, faithful: true)
        }
        if iconvCharsets.contains(name) || foundationEncodings[name] != nil, let text = viaIconv(data, from: name) {
            return DecodedText(text: text, faithful: true)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: text, faithful: name == "utf-8")
        }
        return DecodedText(
            text: "[text in unsupported or invalid charset \"\(name)\" was not decoded]", faithful: false)
    }

    private static func viaIconv(_ data: Data, from charset: String) -> String? {
        let descriptor = iconv_open("UTF-8", charset)
        guard descriptor != iconv_t(bitPattern: -1) else { return nil }
        defer { iconv_close(descriptor) }
        var input = [CChar](data.map { CChar(bitPattern: $0) })
        var output = [CChar](repeating: 0, count: max(16, data.count * 4 + 16))
        let converted: Int? = input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                var inPointer: UnsafeMutablePointer<CChar>? = inBuffer.baseAddress
                var outPointer: UnsafeMutablePointer<CChar>? = outBuffer.baseAddress
                var inLeft = inBuffer.count
                var outLeft = outBuffer.count
                let result = iconv(descriptor, &inPointer, &inLeft, &outPointer, &outLeft)
                guard result != -1 || inLeft == 0 else { return nil }
                return outBuffer.count - outLeft
            }
        }
        guard let converted else { return nil }
        return String(decoding: output.prefix(converted).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
