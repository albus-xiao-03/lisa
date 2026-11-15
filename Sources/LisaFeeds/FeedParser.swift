// Parses RSS 2.0, RSS 1.0 (RDF) and Atom 1.0 feeds into entries with titles, links, summaries and dates.

import Foundation
import LisaTime
import LisaXML

/// A feed's format.
public enum FeedFormat: String, Hashable, Sendable {
    case rss2
    case rss1
    case atom
}

/// One feed entry. Summaries and content are HTML as published; callers convert them to sanitized text.
public struct FeedEntry: Hashable, Sendable {
    public var id: String?
    public var title: String
    public var link: String?
    public var summaryHTML: String?
    public var contentHTML: String?
    public var published: Date?
    public var updated: Date?
    public var categories: [String]
    public var author: String?
}

/// A parsed feed.
public struct FeedDocument: Hashable, Sendable {
    public var format: FeedFormat
    public var title: String?
    public var link: String?
    public var entries: [FeedEntry]
    /// Visible problems, for example a feed that needed error recovery.
    public var warnings: [String]
}

/// Why a document is not a usable feed.
public enum FeedError: Error, Hashable, Sendable, CustomStringConvertible {
    case notAFeed
    case unreadable(String)

    public var description: String {
        switch self {
        case .notAFeed: "the document is not an RSS or Atom feed"
        case .unreadable(let reason): "the feed could not be read: \(reason)"
        }
    }
}

/// Feed parsing on top of ``SafeXMLReader``.
public enum FeedParser {
    private static let atomNamespace = "http://www.w3.org/2005/Atom"
    private static let contentNamespace = "http://purl.org/rss/1.0/modules/content/"
    private static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"

    public static func parse(_ data: Data, maxEntries: Int = 500, limits: XMLReadLimits = XMLReadLimits()) throws
        -> FeedDocument
    {
        let result: XMLDocumentResult
        do {
            result = try SafeXMLReader.parseXML(data, limits: limits)
        } catch {
            throw FeedError.unreadable(String(describing: error))
        }
        var warnings: [String] = []
        if result.recovered { warnings.append("the feed is not well-formed; entries were read with error recovery") }
        if result.normalizedEntityReferences > 0 {
            warnings.append(
                "\(result.normalizedEntityReferences) undefined entity references were kept as visible text or characters"
            )
        }
        let root = result.root
        var document: FeedDocument
        switch root.name.lowercased() {
        case "rss":
            guard let channel = root.element("channel") else { throw FeedError.notAFeed }
            document = FeedDocument(
                format: .rss2, title: text(channel.element("title")), link: text(channel.element("link")),
                entries: channel.elements("item").map(rssItem), warnings: warnings)
        case "rdf":
            let channel = root.element("channel")
            document = FeedDocument(
                format: .rss1, title: text(channel?.element("title")), link: text(channel?.element("link")),
                entries: root.elements("item").map(rssItem), warnings: warnings)
        case "feed":
            document = FeedDocument(
                format: .atom, title: text(root.element("title")), link: atomLink(root),
                entries: root.elements("entry").map(atomEntry), warnings: warnings)
        default:
            throw FeedError.notAFeed
        }
        if document.entries.count > maxEntries {
            document.warnings.append(
                "the feed has \(document.entries.count) entries; only the first \(maxEntries) were read")
            document.entries = Array(document.entries.prefix(maxEntries))
        }
        return document
    }

    private static func text(_ node: XMLNode?) -> String? {
        guard let value = node?.textContent.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func rssItem(_ item: XMLNode) -> FeedEntry {
        let date =
            text(item.element("pubDate")).flatMap(InternetDateParser.parse)
            ?? text(item.element("date", namespace: dublinCoreNamespace)).flatMap(InternetDateParser.parse)
        return FeedEntry(
            id: text(item.element("guid")) ?? item.attributes["about"],
            title: text(item.element("title")) ?? "(untitled)",
            link: text(item.element("link")),
            summaryHTML: text(item.element("description")),
            contentHTML: text(item.element("encoded", namespace: contentNamespace)),
            published: date, updated: nil,
            categories: item.elements("category").compactMap(text),
            author: text(item.element("author")) ?? text(item.element("creator", namespace: dublinCoreNamespace)))
    }

    private static func atomEntry(_ entry: XMLNode) -> FeedEntry {
        FeedEntry(
            id: text(entry.element("id")),
            title: text(entry.element("title")) ?? "(untitled)",
            link: atomLink(entry),
            summaryHTML: text(entry.element("summary")),
            contentHTML: text(entry.element("content")),
            published: text(entry.element("published")).flatMap(InternetDateParser.parseISO8601),
            updated: text(entry.element("updated")).flatMap(InternetDateParser.parseISO8601),
            categories: entry.elements("category").compactMap { $0.attributes["term"] },
            author: text(entry.element("author")?.element("name")))
    }

    private static func atomLink(_ node: XMLNode) -> String? {
        let links = node.elements("link")
        let alternate = links.first { ($0.attributes["rel"] ?? "alternate") == "alternate" }
        return (alternate ?? links.first)?.attributes["href"]
    }
}
