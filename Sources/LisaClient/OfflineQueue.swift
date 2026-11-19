// The durable offline queue (UI-03, NOTIFY-05, L21, L30): enqueueing with stable request IDs, inspection, resolution.

import Foundation
import LisaAPIContract

/// A durable queue of mutations for the host, kept through a `QueueStorage`.
///
/// - Every entry gets its request ID once, at enqueue time, and every attempt sends that ID, so the host applies each
///   request once however often it is retried (API-03).
/// - `flush(using:)` sends entries in order and records each answer on its entry.
/// - Pending entries stay visible until the host confirms them. Conflicts and failures stay until the owner resolves
///   them with `discard(_:)` or `requeue(_:expectedRevision:)`.
/// - Enqueueing a request ID that is already queued for the same request returns the queued entry instead of adding
///   it again.
///
/// Use one queue per storage: the queue does not coordinate with other processes that write the same storage.
public actor OfflineQueue {
    let storage: any QueueStorage
    let configuration: OfflineQueueConfiguration
    let clock: @Sendable () -> Date
    /// The entries, in queue order.
    var entries: [QueuedRequest]
    /// Whether a flush is running.
    var isFlushing = false

    /// Loads the queue from `storage`.
    ///
    /// Entries that were being sent when the process stopped become pending again with their request IDs. The host
    /// may have applied them, so they are marked uncertain (`QueuedRequest.uncertainSince`).
    public init(
        storage: any QueueStorage, configuration: OfflineQueueConfiguration = OfflineQueueConfiguration(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        var loaded = try storage.load()
        var recovered = false
        for index in loaded.indices where loaded[index].status == .sending {
            loaded[index].status = .pending
            if loaded[index].uncertainSince == nil {
                loaded[index].uncertainSince = loaded[index].lastAttemptAt ?? loaded[index].createdAt
            }
            recovered = true
        }
        self.storage = storage
        self.configuration = configuration
        self.clock = clock
        entries = loaded
        if recovered {
            // Saving now is an optimization: until a later save succeeds, loading recovers the same entries again.
            try? storage.save(loaded)
        }
    }

    // MARK: - Enqueueing

    /// Adds `mutation` to the end of the queue and saves the queue.
    ///
    /// - Parameter requestID: the stable request ID; a random lowercase UUID when `nil`. When an entry with this ID is
    ///   already queued for the same route and body, that entry is returned unchanged.
    /// - Throws: `OfflineQueueError` for an invalid or reused request ID, a body larger than the host accepts or a
    ///   full queue; the storage's error when the queue cannot be saved. Nothing is queued when it throws.
    @discardableResult
    public func enqueue(_ mutation: QueuedMutation, requestID: String? = nil) throws -> QueuedRequest {
        let id = requestID ?? RequestID.random()
        guard RequestID.isValid(id) else { throw OfflineQueueError.invalidRequestID(id) }
        let body: Data
        do {
            body = try mutation.body()
        } catch {
            throw OfflineQueueError.encoding("the \(mutation.kind.rawValue) request could not be encoded as JSON")
        }
        let route = mutation.route
        if let existing = entries.first(where: { $0.id == id }) {
            guard existing.method == route.method, existing.path == route.path, existing.body == body else {
                throw OfflineQueueError.requestIDReused(id)
            }
            return existing
        }
        guard body.count <= APIVersioning.maxRequestBytes else {
            throw OfflineQueueError.bodyTooLarge(bytes: body.count, limit: APIVersioning.maxRequestBytes)
        }
        let now = clock()
        var updated = entries
        pruneCompleted(&updated, now: now)
        let bytes = updated.reduce(body.count) { $0 + $1.body.count }
        guard updated.count < configuration.capacity, bytes <= configuration.maxTotalBodyBytes else {
            throw OfflineQueueError.full(entryLimit: configuration.capacity, byteLimit: configuration.maxTotalBodyBytes)
        }
        let entry = QueuedRequest(id: id, mutation: mutation, body: body, createdAt: now)
        updated.append(entry)
        try storage.save(updated)
        entries = updated
        return entry
    }

    /// Queues `mutation` durably, then tries to send it within `timeLimit`. The queue is flushed in order, so earlier
    /// pending entries go first; when the host is unreachable or slow, the entry stays pending for a later flush.
    ///
    /// - Returns: the entry as it stands afterwards: done, pending, a conflict or a failure.
    public func submit(
        _ mutation: QueuedMutation, requestID: String? = nil, using client: LisaAPIClient, timeLimit: Duration
    ) async throws -> QueuedRequest {
        let queued = try enqueue(mutation, requestID: requestID)
        if queued.isAwaitingHost {
            _ = await flush(using: client, timeLimit: timeLimit)
        }
        return entry(queued.id) ?? queued
    }

    // MARK: - Inspection

    /// Every entry, in queue order.
    public var allEntries: [QueuedRequest] { entries }

    /// The entry with this identifier.
    public func entry(_ id: String) -> QueuedRequest? {
        entries.first { $0.id == id }
    }

    /// Entries that still wait for the host (pending or being sent), in order. Show them as pending until the host
    /// confirms them.
    public var pendingEntries: [QueuedRequest] { entries.filter(\.isAwaitingHost) }

    /// Entries the host refused because their subject changed. Resolve them with `discard(_:)`, or with
    /// `requeue(_:expectedRevision:)` after the owner has seen the current state.
    public var conflictEntries: [QueuedRequest] { entries.filter { $0.status == .conflict } }

    /// Entries the host refused for another reason, or whose retry period ended.
    public var failedEntries: [QueuedRequest] { entries.filter { $0.status == .failed } }

    /// Entries the host applied, with their responses, until they are pruned.
    public var completedEntries: [QueuedRequest] { entries.filter { $0.status == .done } }

    // MARK: - Resolution

    /// Removes an entry that is not being sent. Discarding a pending entry that was attempted before does not undo
    /// it if the host already applied it.
    public func discard(_ id: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw OfflineQueueError.entryNotFound(id) }
        guard entries[index].status != .sending else { throw OfflineQueueError.notAllowed(id: id, status: .sending) }
        var updated = entries
        updated.remove(at: index)
        try storage.save(updated)
        entries = updated
    }

    /// Makes a conflicting or failed entry pending again, as a new request with a new request ID, because the host
    /// refused the earlier one. The entry keeps its identity and its place in the queue.
    ///
    /// - Parameter expectedRevision: for a conflict, the revision the owner has now seen, such as the entry's
    ///   `serverRevision` after reviewing the current state. It replaces the expected revision in the body.
    /// - Important: an entry that failed because its retry period ended may already have been applied; re-queue it
    ///   only after checking the item.
    @discardableResult
    public func requeue(_ id: String, expectedRevision: Int64? = nil) throws -> QueuedRequest {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw OfflineQueueError.entryNotFound(id) }
        var entry = entries[index]
        guard entry.needsResolution else { throw OfflineQueueError.notAllowed(id: id, status: entry.status) }
        if let expectedRevision {
            guard let revised = try entry.mutation().expecting(revision: expectedRevision) else {
                throw OfflineQueueError.revisionNotApplicable(entry.kind)
            }
            do {
                entry.body = try revised.body()
            } catch {
                throw OfflineQueueError.encoding("the \(entry.kind.rawValue) request could not be encoded as JSON")
            }
        }
        entry.requestID = RequestID.random()
        entry.status = .pending
        entry.attempts = 0
        entry.lastAttemptAt = nil
        entry.nextAttemptAt = nil
        entry.uncertainSince = nil
        entry.lastError = nil
        entry.serverRevision = nil
        entry.response = nil
        entry.completedAt = nil
        var updated = entries
        updated[index] = entry
        try storage.save(updated)
        entries = updated
        return entry
    }

    // MARK: - Maintenance

    /// Removes applied entries whose retention has passed.
    func pruneCompleted(_ list: inout [QueuedRequest], now: Date) {
        let retention = configuration.completedRetention
        list.removeAll { entry in
            entry.status == .done && (entry.completedAt ?? entry.createdAt).addingTimeInterval(retention) <= now
        }
    }

    /// How many entries wait for the host.
    var awaitingCount: Int { entries.count(where: \.isAwaitingHost) }
}
