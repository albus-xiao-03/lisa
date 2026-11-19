// NEWS-01: ranks news by explicit interests, source preference, recency and feedback, removing duplicates.

import Foundation
import LisaDomain

/// A ranked item with a short reason it was selected.
public struct RankedNews: Sendable {
    public var item: NewsItem
    public var score: Double
    public var reason: String
}

/// Owner signals used for ranking.
public struct RankingSignals: Hashable, Sendable {
    public var interests: [String]
    public var mutedSources: Set<SourceID>
    public var mutedTopics: Set<String>
    /// Per source: a multiplier from owner preference (1 is neutral).
    public var sourceWeights: [SourceID: Double]
    /// Topics the owner asked for more (positive) or less (negative) of.
    public var topicFeedback: [String: Double]

    public init(
        interests: [String], mutedSources: Set<SourceID> = [], mutedTopics: Set<String> = [],
        sourceWeights: [SourceID: Double] = [:], topicFeedback: [String: Double] = [:]
    ) {
        self.interests = interests
        self.mutedSources = mutedSources
        self.mutedTopics = Set(mutedTopics.map { $0.lowercased() })
        self.sourceWeights = sourceWeights
        self.topicFeedback = topicFeedback
    }
}

/// Deterministic news ranking.
public enum NewsRanker {
    /// Ranks `items` and returns at most `limit`. Items with no interest match and no positive feedback are left out.
    public static func rank(_ items: [NewsItem], signals: RankingSignals, now: Date, limit: Int) -> [RankedNews] {
        var seen = Set<String>()
        var seenTitles: [Set<String>] = []
        var ranked: [RankedNews] = []
        let interests = signals.interests.map { $0.lowercased() }.filter { !$0.isEmpty }
        for item in items.sorted(by: {
            ($0.publishedAt ?? $0.retrievedAt, $0.id) > ($1.publishedAt ?? $1.retrievedAt, $1.id)
        }) {
            if signals.mutedSources.contains(item.sourceID) { continue }
            let topics = Set(item.topics.map { $0.lowercased() })
            if !topics.isDisjoint(with: signals.mutedTopics) { continue }
            if item.feedback == .lessLikeThis { continue }
            guard !seen.contains(item.dedupKey) else { continue }
            let titleWords = Set(
                item.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            if seenTitles.contains(where: {
                Double($0.intersection(titleWords).count) / Double(max(1, $0.union(titleWords).count)) >= 0.8
            }) {
                continue
            }
            let haystack = ([item.title, item.accessibleText ?? ""] + item.topics).joined(separator: " ").lowercased()
            let matched = interests.filter { haystack.contains($0) }
            let feedback =
                topics.reduce(0) { $0 + (signals.topicFeedback[$1] ?? 0) } + (item.feedback == .moreLikeThis ? 1 : 0)
            guard !matched.isEmpty || feedback > 0 else { continue }
            let age = max(0, now.timeIntervalSince(item.publishedAt ?? item.retrievedAt))
            let recency = pow(0.5, age / 86_400)
            let weight = signals.sourceWeights[item.sourceID] ?? 1
            let accessibility = item.boundary == .titleOnly ? 0.8 : 1
            let score = (Double(matched.count) + max(0, feedback)) * recency * weight * accessibility
            var reason =
                matched.isEmpty
                ? "You asked for more like this"
                : "Matches your interest in \(matched.map { "\"\($0)\"" }.joined(separator: ", "))"
            if item.isSharedContent { reason += "; shared by you" }
            if item.boundary == .titleOnly { reason += "; only the title was available" }
            seen.insert(item.dedupKey)
            seenTitles.append(titleWords)
            ranked.append(RankedNews(item: item, score: score, reason: reason))
        }
        return Array(ranked.sorted { ($0.score, $0.item.id) > ($1.score, $1.item.id) }.prefix(limit))
    }
}
