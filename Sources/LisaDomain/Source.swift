// A configured information source with its cursor, attempt history, freshness and last failure.

import Foundation

/// The kinds of source Lisa can read from.
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case mailbox
    case calendarFeed
    case newsFeed
    case xAccount
    case discordChannel
    case manualCapture
    case localImport
}

/// Classifies why a synchronization attempt failed, so retries and health reporting can react appropriately.
public enum SourceErrorClass: String, Codable, Sendable {
    case network
    case timeout
    case authentication
    case permissionDenied
    case capabilityDenied
    case rateLimited
    case parse
    case partial
    case configuration
    case unsupported
    case internalError

    /// Whether a later automatic retry can reasonably succeed without owner action.
    public var isRetryable: Bool {
        switch self {
        case .network, .timeout, .rateLimited, .partial, .internalError: true
        case .authentication, .permissionDenied, .capabilityDenied, .parse, .configuration, .unsupported: false
        }
    }
}

/// How current a source's data is.
public enum SourceFreshness: String, Codable, Sendable {
    case fresh
    case stale
    case neverSynchronized
    case disabled
}

/// The most recent failure, described without private content.
public struct SourceFailure: Hashable, Codable, Sendable {
    public var errorClass: SourceErrorClass
    public var summary: String
    public var occurredAt: Date
    public var retryAfter: Date?

    public init(errorClass: SourceErrorClass, summary: String, occurredAt: Date, retryAfter: Date? = nil) {
        self.errorClass = errorClass
        self.summary = summary
        self.occurredAt = occurredAt
        self.retryAfter = retryAfter
    }
}

/// A configured source. Secrets are never stored here; `configurationKey` names the configuration entry.
public struct Source: Entity {
    public static let collectionName = "sources"
    public let id: SourceID
    public var revision: Revision
    public var updatedAt: Date
    public var kind: SourceKind
    public var name: String
    public var configurationKey: String
    public var enabled: Bool
    /// The durable position after the last fully processed item; never advanced past unprocessed data.
    public var cursor: String?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastFailure: SourceFailure?
    public var staleAfterSeconds: Int
    /// Capability limitations surfaced to the owner, such as missing message-content access.
    public var capabilityNotes: [String]
    /// Whether previously imported records are kept when the source is disabled or removed.
    public var retainImportedOnDisable: Bool

    public init(
        id: SourceID = .random(), kind: SourceKind, name: String, configurationKey: String, enabled: Bool = true,
        staleAfterSeconds: Int = 6 * 3600, retainImportedOnDisable: Bool = true, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.kind = kind
        self.name = name
        self.configurationKey = configurationKey
        self.enabled = enabled
        self.cursor = nil
        self.lastAttemptAt = nil
        self.lastSuccessAt = nil
        self.lastFailure = nil
        self.staleAfterSeconds = staleAfterSeconds
        self.capabilityNotes = []
        self.retainImportedOnDisable = retainImportedOnDisable
    }

    /// The source's freshness at `now`.
    public func freshness(at now: Date) -> SourceFreshness {
        guard enabled else { return .disabled }
        guard let lastSuccessAt else { return .neverSynchronized }
        return now.timeIntervalSince(lastSuccessAt) > TimeInterval(staleAfterSeconds) ? .stale : .fresh
    }

    /// Whether the most recent attempt failed after the last success.
    public var isFailing: Bool {
        guard let lastFailure else { return false }
        guard let lastSuccessAt else { return true }
        return lastFailure.occurredAt > lastSuccessAt
    }
}
