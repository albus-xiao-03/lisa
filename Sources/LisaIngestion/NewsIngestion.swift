// News ingestion (NEWS-01): RSS/Atom entries and social posts become news items with evidence and stable keys.

import Foundation
import LisaDomain
import LisaFeeds
import LisaHTMLText
import LisaPorts
import LisaTime

/// Stores feed entries and posts. Keys are per source; cross-source duplicates are grouped by ranking.
public struct NewsBatchProcessor: BatchProcessor {
    public struct PreparedEntry: Sendable {
        var dedupKey: String
        var title: String
        var link: String?
        var text: String?
        var boundary: ContentBoundary
        var publishedAt: Date?
        var topics: [String]
        var rawRef: RawContentRef?
    }

    public struct PreparedNews: Sendable {
        var entries: [PreparedEntry]
        var warnings: [String]
    }

    public static let maxTextCharacters = 4_000
    private let raw: any RawContentStore
    private let clock: any WallClock

    public init(raw: any RawContentStore, clock: any WallClock) {
        self.raw = raw
        self.clock = clock
    }

    public func prepare(_ batch: FetchBatch, source: Source) throws -> PreparedNews {
        let now = clock.now()
        var entries: [PreparedEntry] = []
        var warnings: [String] = []
        for item in batch.items {
            switch item.kind {
            case .feed:
                let document: FeedDocument
                do {
                    document = try FeedParser.parse(item.data)
                } catch {
                    throw ConnectorError(.parse, "the feed could not be read: \(error)")
                }
                warnings += document.warnings.prefix(3)
                let ref = try raw.put(item.data, kind: "feed", now: now)
                for entry in document.entries {
                    let html = entry.contentHTML ?? entry.summaryHTML
                    let text = html.map { String(HTMLText.convert($0).text.prefix(Self.maxTextCharacters)) }
                    let identity = entry.id ?? entry.link ?? "title:\(entry.title)"
                    entries.append(
                        PreparedEntry(
                            dedupKey: "\(source.id.rawValue)|\(identity)", title: String(entry.title.prefix(300)),
                            link: entry.link, text: text?.isEmpty == true ? nil : text,
                            boundary: entry.contentHTML != nil
                                ? .fullText : (entry.summaryHTML != nil ? .feedSummary : .titleOnly),
                            publishedAt: entry.published ?? entry.updated,
                            topics: Array(entry.categories.map { $0.lowercased() }.prefix(10)), rawRef: ref))
                }
            case .post:
                guard let text = String(data: item.data, encoding: .utf8) else {
                    warnings.append("a post that is not UTF-8 text was skipped")
                    continue
                }
                let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
                entries.append(
                    PreparedEntry(
                        dedupKey: "\(source.id.rawValue)|\(item.externalID)",
                        title: String((item.metadata["title"] ?? firstLine).prefix(120)), link: item.metadata["url"],
                        text: String(text.prefix(Self.maxTextCharacters)), boundary: .fullText,
                        publishedAt: item.receivedAt, topics: [], rawRef: nil))
            case .email, .calendar, .page:
                warnings.append("an item of kind \(item.kind) is not news and was skipped")
            }
        }
        return PreparedNews(entries: entries, warnings: warnings)
    }

    public func commit(_ prepared: PreparedNews, batch: FetchBatch, source: Source, in tx: any RecordWriting) throws
        -> IngestionOutcome
    {
        let now = clock.now()
        var outcome = IngestionOutcome()
        outcome.warnings = prepared.warnings
        let evidenceKind: EvidenceKind =
            switch source.kind {
            case .xAccount: .xPost
            case .discordChannel: .discordMessage
            default: .news
            }
        var seen: Set<String> = []
        for entry in prepared.entries where !seen.contains(entry.dedupKey) {
            seen.insert(entry.dedupKey)
            if try tx.first(NewsItem.self, RecordQuery.all.filter("dedup_key", equals: entry.dedupKey)) != nil {
                outcome.unchanged += 1
                continue
            }
            let evidence = try tx.insert(
                Evidence(
                    kind: evidenceKind, sourceID: source.id, externalID: entry.dedupKey, capturedAt: now,
                    occurredAt: entry.publishedAt, excerpt: String((entry.text ?? entry.title).prefix(280)),
                    contentRef: entry.rawRef?.value))
            try tx.insert(
                NewsItem(
                    sourceID: source.id, originalURL: entry.link, title: entry.title, accessibleText: entry.text,
                    boundary: entry.boundary, publishedAt: entry.publishedAt, retrievedAt: now, topics: entry.topics,
                    dedupKey: entry.dedupKey, evidenceID: evidence.id))
            outcome.inserted += 1
        }
        return outcome
    }
}
