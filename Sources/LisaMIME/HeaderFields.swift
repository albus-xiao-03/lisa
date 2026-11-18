// Message header blocks: unfolding and name/value splitting, bounded in size and count.

import Foundation

/// One header field with its raw (undecoded) value.
public struct HeaderField: Hashable, Sendable {
    public let name: String
    public let value: String
}

/// An ordered list of header fields with case-insensitive lookup.
public struct HeaderFields: Hashable, Sendable {
    public private(set) var fields: [HeaderField]

    public init(_ fields: [HeaderField]) {
        self.fields = fields
    }

    /// The first value of `name`.
    public func value(_ name: String) -> String? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Every value of `name`.
    public func values(_ name: String) -> [String] {
        fields.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    /// Parses a header block, keeping at most `limits.maxHeaderFields` fields; `truncated` says that more were present.
    /// Raw 8-bit headers are read as UTF-8 when valid, otherwise as ISO-8859-1.
    static func parse(_ data: Data, limits: MIMELimits) throws -> (fields: HeaderFields, truncated: Bool) {
        guard data.count <= limits.maxHeaderBytes else { throw MIMEError.headersTooLarge }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data.map { $0 }, as: Unicode.ASCII.self)
        let latin = String(data: data, encoding: .isoLatin1) ?? text
        let source = String(data: data, encoding: .utf8) == nil ? latin : text
        var fields: [HeaderField] = []
        var currentName: String?
        var currentValue = ""
        var truncated = false
        func flush() {
            if let currentName { fields.append(HeaderField(name: currentName, value: currentValue)) }
        }
        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var line = Substring(rawLine)
            if line.last == "\r" { line = line.dropLast() }
            if line.isEmpty { continue }
            if let first = line.first, first == " " || first == "\t" {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            flush()
            guard fields.count < limits.maxHeaderFields else {
                truncated = true
                currentName = nil
                break
            }
            currentName = line[..<colon].trimmingCharacters(in: .whitespaces)
            currentValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        flush()
        return (HeaderFields(fields), truncated)
    }
}
