// A news item with its origin, times, accessible-content boundary and the reason it was selected.

import Foundation

/// How much of an article Lisa could actually read. Title-only items are never summarized as if read.
public enum ContentBoundary: String, Codable, Sendable {
    case titleOnly
    case feedSummary
    case fullText
    case sharedText
    /// The visible text of the page behind a link the owner captured, read once at the owner's request as an
    /// anonymous reader is served it, with no scripts run. For a paywalled or sign-in page that can be only the public
    /// part, so it is never presented as the full article.
    case pageText
}

/// The owner's feedback on an item.
public enum NewsFeedback: String, Codable, Sendable {
    case moreLikeThis
    case lessLikeThis
}

/// A news item from a feed, a post, a channel message or an owner share.
public struct NewsItem: Entity {
    public static let collectionName = "news"
    public let id: NewsID
    public var revision: Revision
    public var updatedAt: Date
    public var sourceID: SourceID
    public var originalURL: String?
    public var title: String
    public var accessibleText: String?
    public var boundary: ContentBoundary
    public var publishedAt: Date?
    public var retrievedAt: Date
    /// Shared by the owner (for example from Apple News); labeled as shared content.
    public var isSharedContent: Bool
    public var sharedFrom: String?
    public var topics: [String]
    /// Stable duplicate-detection key (normalized URL or normalized title).
    public var dedupKey: String
    public var relevanceScore: Double?
    public var relevanceReason: String?
    public var feedback: NewsFeedback?
    public var evidenceID: EvidenceID
    /// The address that served the page Lisa read for this item at the owner's request, after any redirects; `nil`
    /// until then. A captured link's page is read once.
    public var pageURL: String?

    public init(
        id: NewsID = .random(), sourceID: SourceID, originalURL: String?, title: String, accessibleText: String?,
        boundary: ContentBoundary, publishedAt: Date?, retrievedAt: Date, isSharedContent: Bool = false,
        sharedFrom: String? = nil, topics: [String] = [], dedupKey: String, evidenceID: EvidenceID
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = retrievedAt
        self.sourceID = sourceID
        self.originalURL = originalURL
        self.title = title
        self.accessibleText = accessibleText
        self.boundary = boundary
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
        self.isSharedContent = isSharedContent
        self.sharedFrom = sharedFrom
        self.topics = topics
        self.dedupKey = dedupKey
        self.relevanceScore = nil
        self.relevanceReason = nil
        self.feedback = nil
        self.evidenceID = evidenceID
        self.pageURL = nil
    }
}
