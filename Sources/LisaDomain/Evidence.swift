// Evidence: the original material that every extracted item and summarized claim traces back to.

import Foundation

/// The kind of material a piece of evidence came from.
public enum EvidenceKind: String, Codable, Sendable {
    case email
    case calendar
    case news
    case capture
    case xPost
    case discordMessage
}

/// A bounded excerpt of original source material, kept separately from anything generated from it.
public struct Evidence: Entity {
    public static let collectionName = "evidence"
    public let id: EvidenceID
    public var revision: Revision
    public var updatedAt: Date
    public var kind: EvidenceKind
    public var sourceID: SourceID
    /// The source-specific identity, such as an IMAP UID key, an iCalendar UID or a URL.
    public var externalID: String
    public var capturedAt: Date
    public var occurredAt: Date?
    /// The original text excerpt, bounded in size.
    public var excerpt: String
    /// A reference to retained raw content, when retention keeps it.
    public var contentRef: String?

    public init(
        id: EvidenceID = .random(), kind: EvidenceKind, sourceID: SourceID, externalID: String, capturedAt: Date,
        occurredAt: Date? = nil, excerpt: String, contentRef: String? = nil
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = capturedAt
        self.kind = kind
        self.sourceID = sourceID
        self.externalID = externalID
        self.capturedAt = capturedAt
        self.occurredAt = occurredAt
        self.excerpt = excerpt
        self.contentRef = contentRef
    }
}
