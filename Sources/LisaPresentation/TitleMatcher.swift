// Finding tasks or reminders by a spoken or typed name, keeping every match for disambiguation (SIRI-01).

import Foundation

/// Finds items by name. Every match is returned, so the caller can ask which one was meant when several match
/// (SIRI-01: clear disambiguation); the caller then acts on the chosen item's stable identifier.
public enum TitleMatcher {
    /// The items whose title contains every word of `query`, ignoring case and diacritics. An exact title comes
    /// first, then titles that start with the query, then the rest, each group in the given order. An empty query
    /// matches nothing.
    public static func matches<Item>(_ query: String, in items: [Item], title: (Item) -> String) -> [Item] {
        let wanted = normalized(query)
        let words = wanted.split(separator: " ")
        guard !words.isEmpty else { return [] }
        var exact: [Item] = []
        var prefixed: [Item] = []
        var containing: [Item] = []
        for item in items {
            let name = normalized(title(item))
            guard words.allSatisfy({ name.contains($0) }) else { continue }
            if name == wanted {
                exact.append(item)
            } else if name.hasPrefix(wanted) {
                prefixed.append(item)
            } else {
                containing.append(item)
            }
        }
        return exact + prefixed + containing
    }

    /// Lowercase text without diacritics, with runs of whitespace and punctuation as single spaces.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { $0.isWhitespace || $0.isPunctuation }
            .joined(separator: " ")
    }
}
