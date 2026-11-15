// Content-Type and Content-Disposition values with parameters (quoted values and RFC 2231 continuations).

import Foundation

/// A parsed `type/subtype; name=value` header value.
public struct ContentType: Hashable, Sendable {
    public var type: String
    public var subtype: String
    public var parameters: [String: String]

    public var mimeType: String { "\(type)/\(subtype)" }

    public var charset: String? { parameters["charset"] }

    public var boundary: String? { parameters["boundary"] }

    /// `text/plain; charset=us-ascii`, the RFC 2045 default.
    public static let defaultText = ContentType(type: "text", subtype: "plain", parameters: ["charset": "us-ascii"])

    public init(type: String, subtype: String, parameters: [String: String]) {
        self.type = type
        self.subtype = subtype
        self.parameters = parameters
    }

    /// Parses a Content-Type value, or returns `nil` when it has no `type/subtype`.
    public init?(_ value: String) {
        let segments = HeaderParameters.split(value)
        guard let head = segments.first else { return nil }
        let pieces = head.lowercased().split(separator: "/", maxSplits: 1)
        guard pieces.count == 2 else { return nil }
        type = pieces[0].trimmingCharacters(in: .whitespaces)
        subtype = pieces[1].trimmingCharacters(in: .whitespaces)
        parameters = HeaderParameters.parse(Array(segments.dropFirst()))
    }
}

/// A parsed Content-Disposition value.
public struct ContentDisposition: Hashable, Sendable {
    public var isAttachment: Bool
    public var filename: String?

    public init?(_ value: String?) {
        guard let value else { return nil }
        let segments = HeaderParameters.split(value)
        guard let head = segments.first else { return nil }
        isAttachment = head.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
        filename = HeaderParameters.parse(Array(segments.dropFirst()))["filename"].map(EncodedWords.decode)
    }
}

/// Shared parameter parsing for structured MIME header values.
enum HeaderParameters {
    /// Splits on semicolons outside quotes.
    static func split(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for character in value {
            if character == "\"" { inQuotes.toggle() }
            if character == ";" && !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Parses `name=value` pairs, joining RFC 2231 continuations (`name*0=`, `name*1*=`) and decoding `name*=`.
    static func parse(_ segments: [String]) -> [String: String] {
        var simple: [String: String] = [:]
        var continued: [String: [(Int, String, Bool)]] = [:]
        for segment in segments {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
            }
            let keyParts = key.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
            if keyParts.count >= 2, let index = Int(keyParts[1]) {
                continued[keyParts[0], default: []].append((index, value, keyParts.count == 3))
            } else if keyParts.count == 2, keyParts[1].isEmpty {
                simple[keyParts[0]] = decodeExtended(value)
            } else {
                simple[key] = value
            }
        }
        for (name, pieces) in continued {
            let joined = pieces.sorted { $0.0 < $1.0 }.map {
                $0.2 ? decodeExtended($0.1, allowCharsetPrefix: $0.0 == 0) : $0.1
            }
            simple[name] = joined.joined()
        }
        return simple
    }

    /// Decodes an RFC 2231 extended value such as `utf-8''na%C3%AFve.txt`.
    static func decodeExtended(_ value: String, allowCharsetPrefix: Bool = true) -> String {
        var charset = "utf-8"
        var encoded = Substring(value)
        if allowCharsetPrefix {
            let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
            if pieces.count == 3 {
                charset = String(pieces[0]).isEmpty ? "utf-8" : String(pieces[0])
                encoded = pieces[2]
            }
        }
        var bytes = Data()
        var iterator = encoded.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == UInt8(ascii: "%"), let high = iterator.next(), let low = iterator.next(),
                let value = UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16)
            {
                bytes.append(value)
            } else {
                bytes.append(byte)
            }
        }
        return CharsetDecoder.decode(bytes, charset: charset).text
    }
}
