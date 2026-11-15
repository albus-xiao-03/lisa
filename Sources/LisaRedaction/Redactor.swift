// Rules that turn private values into log-safe forms: fingerprints, host-only URLs and bounded excerpts.

import Foundation

/// Produces log-safe representations of private values.
public enum Redactor {
    /// A short, stable, non-reversible fingerprint (16 hexadecimal digits of FNV-1a 64) for correlating a value
    /// across log lines without revealing it. It is not a security primitive and never authenticates anything.
    public static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Keeps only the scheme and host of a URL, so private paths, query tokens and user information never reach logs.
    public static func hostOnly(_ url: String) -> String {
        guard let schemeEnd = url.range(of: "://") else { return "<redacted-url>" }
        let scheme = url[..<schemeEnd.lowerBound]
        var rest = url[schemeEnd.upperBound...]
        if let slash = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            rest = rest[..<slash]
        }
        if let at = rest.lastIndex(of: "@") {
            rest = rest[rest.index(after: at)...]
        }
        guard !rest.isEmpty else { return "<redacted-url>" }
        return "\(scheme)://\(rest)/…"
    }

    /// Replaces an email address with its domain only.
    public static func emailDomain(_ address: String) -> String {
        guard let at = address.lastIndex(of: "@") else { return "<redacted-address>" }
        return "…@" + address[address.index(after: at)...]
    }

    /// Truncates text to at most `limit` characters, marking the cut.
    public static func bounded(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit))) + "…"
    }
}
