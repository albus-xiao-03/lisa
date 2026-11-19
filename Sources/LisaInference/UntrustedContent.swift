// Wraps source material as untrusted data for model prompts, neutralizing delimiters and minimizing private details.

import Foundation

/// Source content prepared for a prompt. Instructions inside it are data, never commands (MODEL-03).
public struct UntrustedContent: Hashable, Sendable {
    static let openMarker = "<<<UNTRUSTED SOURCE CONTENT>>>"
    static let closeMarker = "<<<END UNTRUSTED SOURCE CONTENT>>>"

    /// The text exactly as sent (after minimization and truncation); evidence quotes are checked against it.
    public let text: String
    public let truncated: Bool

    /// Prepares `raw` for a provider at `location`, removing addresses, phone numbers and links for remote providers.
    public init(_ raw: String, minimize: Bool, maxCharacters: Int) {
        var value = raw.replacingOccurrences(of: "<<<", with: "‹‹‹").replacingOccurrences(of: ">>>", with: "›››")
        if minimize {
            value = UntrustedContent.minimized(value)
        }
        truncated = value.count > maxCharacters
        text = truncated ? String(value.prefix(maxCharacters)) : value
    }

    /// The delimited block placed in the user message.
    public var envelope: String {
        "\(UntrustedContent.openMarker)\n\(text)\n\(UntrustedContent.closeMarker)"
    }

    /// Extracts the content from a prompt built with ``envelope`` (used by the in-process provider).
    public static func extract(from prompt: String) -> String? {
        guard let open = prompt.range(of: openMarker + "\n"),
            let close = prompt.range(of: "\n" + closeMarker, range: open.upperBound..<prompt.endIndex)
        else { return nil }
        return String(prompt[open.upperBound..<close.lowerBound])
    }

    static func minimized(_ text: String) -> String {
        var value = text
        let rules: [(String, String)] = [
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[email]"),
            (#"https?://[^\s<>"]+"#, "[link]"),
            (#"\+?\d[\d\s().\-]{7,}\d"#, "[phone]"),
        ]
        for (pattern, replacement) in rules {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value
    }
}
