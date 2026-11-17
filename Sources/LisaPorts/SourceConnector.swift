// The common connector contract (INGEST-01): validated configuration, bounded incremental fetches, typed failures.

import Foundation
import LisaDomain

/// Bounds for one synchronization pass (OPS-02).
public struct SyncLimits: Hashable, Sendable {
    public var maxItems: Int
    public var maxBytes: Int
    public var timeoutSeconds: Int

    public init(maxItems: Int = 200, maxBytes: Int = 50_000_000, timeoutSeconds: Int = 60) {
        self.maxItems = maxItems
        self.maxBytes = maxBytes
        self.timeoutSeconds = timeoutSeconds
    }
}

/// What a fetched item contains.
public enum FetchedItemKind: String, Hashable, Sendable {
    /// An RFC 5322 message.
    case email
    /// A complete iCalendar document (a full subscription refresh).
    case calendar
    /// An RSS or Atom document.
    case feed
    /// A social post or channel message: its text as UTF-8, with the optional `title` and `url` metadata keys.
    case post
    /// An owner-requested web page.
    case page
}

/// One fetched item.
public struct FetchedItem: Hashable, Sendable {
    /// The source-specific identity, such as `imap:<uidvalidity>:<uid>` or a post ID.
    public var externalID: String
    public var kind: FetchedItemKind
    public var data: Data
    public var receivedAt: Date
    public var metadata: [String: String]

    public init(
        externalID: String, kind: FetchedItemKind, data: Data, receivedAt: Date, metadata: [String: String] = [:]
    ) {
        self.externalID = externalID
        self.kind = kind
        self.data = data
        self.receivedAt = receivedAt
        self.metadata = metadata
    }
}

/// One fetch result. A partial or failed retrieval is an error, never an empty batch.
public struct FetchBatch: Hashable, Sendable {
    public var items: [FetchedItem]
    /// Persisted only after every item in this batch is durably processed.
    public var nextCursor: String?
    /// True when the batch is the source's complete current state (a calendar subscription refresh).
    public var isCompleteSnapshot: Bool
    /// More items are waiting; the runtime fetches again in a later bounded pass.
    public var hasMore: Bool
    /// Capability limitations to show the owner, such as missing message-content access.
    public var capabilityNotes: [String]

    public init(
        items: [FetchedItem], nextCursor: String?, isCompleteSnapshot: Bool, hasMore: Bool = false,
        capabilityNotes: [String] = []
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.isCompleteSnapshot = isCompleteSnapshot
        self.hasMore = hasMore
        self.capabilityNotes = capabilityNotes
    }
}

/// A classified connector failure.
public struct ConnectorError: Error, Hashable, Sendable, CustomStringConvertible {
    public var errorClass: SourceErrorClass
    /// A description without secrets or private content.
    public var summary: String
    public var retryAfter: Date?

    public init(_ errorClass: SourceErrorClass, _ summary: String, retryAfter: Date? = nil) {
        self.errorClass = errorClass
        self.summary = summary
        self.retryAfter = retryAfter
    }

    public var description: String { "\(errorClass.rawValue): \(summary)" }
}

/// A source adapter.
public protocol SourceConnector: Sendable {
    var kind: SourceKind { get }
    /// Checks configuration without contacting the service.
    func validateConfiguration() throws
    /// Fetches the next bounded batch after `cursor`. Must honor `limits` and task cancellation.
    func fetch(cursor: String?, limits: SyncLimits) async throws -> FetchBatch
}
