// Canonical URL forms for duplicate detection: lower-cased host, no fragment, no tracking parameters.

import Foundation

/// URL normalization for news deduplication.
public enum URLCanonicalizer {
    private static let trackingPrefixes = ["utm_", "mc_", "fbclid", "gclid", "ref", "cmpid", "ocid"]

    /// The canonical form, or the trimmed input when it is not an absolute HTTP(S) URL.
    public static func canonical(_ text: String) -> String {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        components.scheme = "https"
        components.host = components.host?.lowercased()
        if components.host?.hasPrefix("www.") == true { components.host = String(components.host!.dropFirst(4)) }
        components.fragment = nil
        components.port = nil
        if let items = components.queryItems {
            let kept = items.filter { item in !trackingPrefixes.contains { item.name.lowercased().hasPrefix($0) } }
                .sorted { $0.name < $1.name }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        if components.path.count > 1, components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? text
    }

    /// The dedup key for an item: its canonical URL, or its normalized title when it has no URL.
    public static func dedupKey(url: String?, title: String) -> String {
        if let url, !url.isEmpty { return "url:" + canonical(url) }
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return "title:" + folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
