// How local search breaks text into tokens (plan §8.6.1, the search index): folded for case, diacritics and width, split
// at everything that isn't a letter or a digit, each token at most 64 scalars, each once.

import Foundation

/// Tokens for the local search index and for queries.
public enum SearchTokenizer {
    public static let maximumTokenScalars = 64

    /// The distinct folded tokens of `text`, in their first order.
    public static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var tokens: [String] = []
        var seen: Set<String> = []
        var current = String.UnicodeScalarView()
        func flush() {
            guard !current.isEmpty else { return }
            let token = String(String.UnicodeScalarView(current.prefix(maximumTokenScalars)))
            if seen.insert(token).inserted { tokens.append(token) }
            current = String.UnicodeScalarView()
        }
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { current.append(scalar) } else { flush() }
        }
        flush()
        return tokens
    }
}
