// The common connector runner (INGEST-01): bounded pages, durable progress, classified failures, visible health.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// What a batch processor stored.
public struct IngestionOutcome: Hashable, Sendable {
    public var inserted = 0
    public var updated = 0
    public var unchanged = 0
    public var skipped = 0
    public var changes: [DomainChange] = []
    /// New records that need interpretation (for example emails awaiting extraction).
    public var pendingReview: [String] = []
    public var warnings: [String] = []

    public init() {}

    mutating func merge(_ other: IngestionOutcome) {
        inserted += other.inserted
        updated += other.updated
        unchanged += other.unchanged
        skipped += other.skipped
        changes += other.changes
        pendingReview += other.pendingReview
        warnings += other.warnings
    }
}

/// Turns fetched items into records. Preparation (parsing, storing raw content, reading settings) happens outside
/// the transaction; `commit` runs inside the transaction that also advances the source cursor and must use only that
/// transaction for storage access.
public protocol BatchProcessor: Sendable {
    associatedtype Prepared
    func prepare(_ batch: FetchBatch, source: Source) throws -> Prepared
    func commit(_ prepared: Prepared, batch: FetchBatch, source: Source, in tx: any RecordWriting) throws
        -> IngestionOutcome
}

/// The result of one synchronization.
public struct SyncReport: Sendable {
    public var sourceID: SourceID
    public var pages = 0
    public var outcome = IngestionOutcome()
    public var failure: SourceFailure?
    /// True when the source was disabled and nothing was fetched.
    public var skippedDisabled = false
    /// True when the run stopped at the page limit with more data available.
    public var morePending = false
}

/// Runs connectors.
public final class ConnectorRunner: Sendable {
    /// Notes kept on a source, newest last.
    public static let maxNotes = 10
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    /// Fetches and processes pages until the source has no more data, `maxPages` is reached or a failure occurs.
    /// The cursor advances only in the transaction that stored a page, so a failure never skips data.
    public func synchronize<P: BatchProcessor>(
        sourceID: SourceID, connector: any SourceConnector, processor: P, limits: SyncLimits = SyncLimits(),
        maxPages: Int = 10
    ) async -> SyncReport {
        var report = SyncReport(sourceID: sourceID)
        do {
            var source = try store.read { try $0.require(Source.self, id: sourceID) }
            guard source.enabled else {
                report.skippedDisabled = true
                return report
            }
            try connector.validateConfiguration()
            while report.pages < max(1, maxPages) {
                try Task.checkCancellation()
                let batch = try await connector.fetch(cursor: source.cursor, limits: limits)
                guard batch.items.count <= limits.maxItems,
                    batch.items.reduce(0, { $0 + $1.data.count }) <= limits.maxBytes
                else {
                    throw ConnectorError(.partial, "the connector returned more than the page limit")
                }
                let prepared = try processor.prepare(batch, source: source)
                let now = clock.now()
                let outcome: IngestionOutcome
                (source, outcome) = try store.write { tx in
                    var current = try tx.require(Source.self, id: sourceID)
                    let outcome = try processor.commit(prepared, batch: batch, source: current, in: tx)
                    current.cursor = batch.nextCursor
                    current.lastAttemptAt = now
                    if !batch.hasMore {
                        current.lastSuccessAt = now
                        current.lastFailure = nil
                    }
                    current.capabilityNotes = Self.notes(
                        current.capabilityNotes, adding: batch.capabilityNotes + outcome.warnings)
                    current.updatedAt = now
                    let saved = try tx.update(current)
                    return (saved, outcome)
                }
                report.pages += 1
                report.outcome.merge(outcome)
                if !batch.hasMore { break }
                if report.pages == maxPages { report.morePending = true }
            }
        } catch {
            let failure = Self.classify(error, at: clock.now())
            report.failure = failure
            do {
                try store.write { tx in
                    guard var source = try tx.get(Source.self, id: sourceID) else { return }
                    source.lastAttemptAt = failure.occurredAt
                    source.lastFailure = failure
                    source.updatedAt = failure.occurredAt
                    try tx.update(source)
                    try tx.insert(
                        AuditEvent(
                            action: "source.sync-failed", actor: .runtime, at: failure.occurredAt,
                            affected: [sourceID.rawValue], outcome: .failed,
                            detail: "class=\(failure.errorClass.rawValue)"))
                }
            } catch {
                logger.error("could not record a source failure", ["source": .public(sourceID.rawValue)])
            }
            logger.warning(
                "source synchronization failed",
                ["source": .public(sourceID.rawValue), "class": .public(failure.errorClass.rawValue)])
        }
        if report.outcome.inserted + report.outcome.updated > 0 {
            logger.info(
                "source synchronized",
                [
                    "source": .public(sourceID.rawValue), "inserted": .count(report.outcome.inserted),
                    "updated": .count(report.outcome.updated), "pages": .count(report.pages),
                ])
        }
        return report
    }

    /// Classifies an error for retry decisions and health. Processing errors are internal; cancellation is a timeout.
    static func classify(_ error: any Error, at now: Date) -> SourceFailure {
        switch error {
        case let connector as ConnectorError:
            return SourceFailure(
                errorClass: connector.errorClass, summary: connector.summary, occurredAt: now,
                retryAfter: connector.retryAfter)
        case is CancellationError:
            return SourceFailure(errorClass: .timeout, summary: "the synchronization was cancelled", occurredAt: now)
        case let store as StoreError:
            return SourceFailure(errorClass: .internalError, summary: store.description, occurredAt: now)
        case let domain as DomainError:
            return SourceFailure(errorClass: .parse, summary: domain.description, occurredAt: now)
        default:
            return SourceFailure(
                errorClass: .internalError, summary: "the data could not be processed", occurredAt: now)
        }
    }

    static func notes(_ existing: [String], adding new: [String]) -> [String] {
        var notes = existing
        for note in new where !notes.contains(note) { notes.append(String(note.prefix(300))) }
        return Array(notes.suffix(maxNotes))
    }
}
