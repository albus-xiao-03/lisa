// Removes an address's path and query from text, so a private address never reaches an error summary or a note.

import Foundation

/// Replaces the full address, its path and its query, in both percent-encoded and decoded forms, with `<redacted>`.
///
/// Summaries are built from Lisa's own wording and show at most the origin; this is a second line of defense for any
/// transport text that is passed through.
package struct SecretScrubber: Sendable {
    /// Shorter fragments (such as the path `/`) carry no secret and would only mangle unrelated text.
    package static let minimumFragmentLength = 4
    package static let replacement = "<redacted>"

    private let fragments: [String]

    package init(url: URL) {
        var candidates = [url.absoluteString]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            candidates.append(components.percentEncodedPath)
            candidates.append(components.path)
            candidates += [components.percentEncodedQuery, components.query].compactMap { $0 }
        }
        // Longest first, so the full address is removed before its parts.
        fragments = Set(candidates.filter { $0.count >= Self.minimumFragmentLength }).sorted {
            $0.count != $1.count ? $0.count > $1.count : $0 < $1
        }
    }

    package func scrub(_ text: String) -> String {
        fragments.reduce(text) { $0.replacingOccurrences(of: $1, with: Self.replacement) }
    }
}
