// Email address lists: quoted display names, comments, angle addresses and groups.

import Foundation

/// An address with an optional display name, as written in a header.
public struct MailAddress: Hashable, Sendable, CustomStringConvertible {
    public var displayName: String?
    public var address: String

    public init(displayName: String?, address: String) {
        self.displayName = displayName
        self.address = address
    }

    public var description: String {
        if let displayName, !displayName.isEmpty { "\(displayName) <\(address)>" } else { address }
    }

    /// Whether `address` is a plausible addr-spec: one `@`, non-empty parts, no whitespace or control characters.
    public static func isValid(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."),
            !parts[1].hasSuffix(".")
        else { return false }
        return !address.unicodeScalars.contains {
            $0.properties.isWhitespace || $0.value < 32 || "<>()[],;:\"".unicodeScalars.contains($0)
        }
    }

    /// Parses an address-list header value. Invalid entries are skipped.
    public static func parseList(_ value: String) -> [MailAddress] {
        let decoded = EncodedWords.decode(value)
        var entries: [String] = []
        var current = ""
        var inQuotes = false
        var angleDepth = 0
        var commentDepth = 0
        for character in decoded {
            switch character {
            case "\"" where commentDepth == 0: inQuotes.toggle()
            case "<" where !inQuotes && commentDepth == 0: angleDepth += 1
            case ">" where !inQuotes && commentDepth == 0: angleDepth = max(0, angleDepth - 1)
            case "(" where !inQuotes: commentDepth += 1
            case ")" where !inQuotes: commentDepth = max(0, commentDepth - 1)
            default: break
            }
            if (character == "," || character == ";") && !inQuotes && angleDepth == 0 && commentDepth == 0 {
                entries.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        entries.append(current)
        return entries.compactMap(parseOne)
    }

    private static func parseOne(_ raw: String) -> MailAddress? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = text.firstIndex(of: ":"), !text[..<colon].contains("<"), !text[..<colon].contains("@") {
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            let address = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces).lowercased()
            var name = text[..<open].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            guard isValid(address) else { return nil }
            return MailAddress(displayName: name.isEmpty ? nil : name, address: address)
        }
        let withoutComment = text.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard isValid(withoutComment) else { return nil }
        return MailAddress(displayName: nil, address: withoutComment)
    }
}
