// The redacted export's scrubbing (plan §10.8 "Redacted export"): free text keeps its meaning but loses addresses,
// numbers, URLs and anything token-like; each becomes a stable per-run alias or a digest.

import Foundation
import LisaCrypto

/// Replaces e-mail addresses, URLs, telephone numbers (international with `+`, or North American with separators), IP
/// addresses and token-like runs of 32 or more characters with stable aliases. A digest the harness wrote as
/// `sha256:<hex>` is evidence, not a secret, and is kept.
public final class VerifyRedactor: @unchecked Sendable {
    private var aliases: [String: String] = [:]
    private var counters: [String: Int] = [:]

    private static let patterns: [(kind: String, regex: NSRegularExpression)] = [
        ("url", #"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+"#),
        ("address", #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        ("number", #"\+[0-9][0-9 ().-]{6,}[0-9]|\(?\b[0-9]{3}\)?[ .-][0-9]{3}[ .-][0-9]{4}\b"#),
        ("ip", #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b|\b(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}\b"#),
        ("token", #"(?<![A-Za-z0-9_\-+/=])(?<!sha256:)[A-Za-z0-9_\-+/=]{32,}"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    public init() {}

    /// The text with every sensitive span replaced by its alias.
    public func scrub(_ text: String) -> String {
        var result = text
        for (kind, regex) in Self.patterns {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: alias(kind, String(result[range])))
            }
        }
        return result
    }

    /// A provider reference, kept only as a digest.
    public func digest(_ reference: String) -> String {
        "sha256:" + Digests.sha256Hex(Data(reference.utf8)).prefix(16)
    }

    private func alias(_ kind: String, _ value: String) -> String {
        if let existing = aliases[value] { return existing }
        let next = (counters[kind] ?? 0) + 1
        counters[kind] = next
        let alias = "<\(kind)-\(next)>"
        aliases[value] = alias
        return alias
    }
}
