// Normalized word tokens for comparing event titles: case- and accent-folded, punctuation and filler words removed.

import Foundation

/// Token sets used by matching.
enum TitleTokens {
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "for", "to", "with", "on", "at", "in", "re", "fw", "fwd", "meeting",
        "call",
        "event", "invitation", "invite", "updated", "accepted",
    ]

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return Set(words.filter { !stopwords.contains($0) && !$0.isEmpty })
    }

    /// Jaccard similarity of two token sets, from 0 to 1.
    static func similarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }
}
