// The pending-actions screen: queued actions waiting for the host, conflicts and failures to resolve, and flushing.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The pending-actions screen (UI-02, UI-03, NOTIFY-05).
///
/// It lists every entry of the offline queue, including the notification actions `NotificationActionHandler` queued:
/// those waiting for the host, the conflicts the owner resolves by applying them again to the current revision or
/// discarding them, and the failures the owner retries or discards. Flushing sends the waiting entries in order with
/// their original request IDs, so the host applies each once. It runs when the owner asks, or on each signal of an
/// injected trigger, such as the app returning to the foreground or the network path becoming available; nothing
/// polls the host.
@MainActor
@Observable
public final class PendingActionsModel {
    /// Entries waiting for the host, in queue order.
    public private(set) var pending: [PendingAction] = []
    /// Entries the host refused because their subject changed.
    public private(set) var conflicts: [PendingAction] = []
    /// Entries the host refused for another reason, or whose retry period ended.
    public private(set) var failures: [PendingAction] = []
    /// Whether a flush is running.
    public private(set) var isFlushing = false
    /// What the latest flush did.
    public private(set) var lastFlush: FlushReport?
    /// When the latest flush finished.
    public private(set) var lastFlushAt: Date?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?

    /// A model over the context's queue that reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    /// How many actions the owner took that wait for the host; notification receipts are not counted.
    public var pendingCount: Int { pending.count { $0.isOwnerAction } }

    /// How many entries need the owner's decision.
    public var attentionCount: Int { conflicts.count + failures.count }

    /// Reads the queue.
    public func reload() async {
        let entries = await context.queue.allEntries.map(PendingAction.init)
        pending = entries.filter(\.isPending)
        conflicts = entries.filter { $0.status == .conflict }
        failures = entries.filter { $0.status == .failed }
    }

    /// Sends the waiting entries in order and records each answer; returns what the flush did.
    @discardableResult
    public func flush() async -> FlushReport {
        isFlushing = true
        defer { isFlushing = false }
        let report = await context.queue.flush(using: context.client)
        if let contact = HostContact(report) { await contacts?.record(contact) }
        lastFlush = report
        lastFlushAt = context.now()
        await reload()
        return report
    }

    /// Flushes once for every signal, for example when the app returns to the foreground or the network path becomes
    /// available. Returns when the signals end or the calling task is cancelled.
    public func flushOnSignals(_ signals: AsyncStream<Void>) async {
        for await _ in signals {
            if Task.isCancelled { break }
            await flush()
        }
    }

    /// Submits a conflict or failure again as a new request. A conflict expects the current revision the host reported,
    /// so call it only after the owner has seen the current state; a failure that may already have been applied
    /// (`mayHaveBeenApplied`) should be checked first.
    @discardableResult
    public func resubmit(_ id: String) async -> ActionOutcome {
        guard let entry = (conflicts + failures).first(where: { $0.id == id }) else {
            return .failed(reason: "this action no longer needs a decision")
        }
        if entry.status == .conflict, entry.currentRevision == nil {
            return .failed(reason: "the item can no longer take this action; discard it")
        }
        let revision = entry.status == .conflict ? entry.currentRevision : nil
        let submission = await ActionSubmitter(context: context).resubmit(id, expectedRevision: revision)
        if let contact = submission.contact { await contacts?.record(contact) }
        await reload()
        return submission.outcome
    }

    /// Removes an entry that is not being sent. Discarding a waiting entry that was attempted before does not undo it
    /// if the host already applied it. Returns whether it was removed.
    @discardableResult
    public func discard(_ id: String) async -> Bool {
        let discarded = (try? await context.queue.discard(id)) != nil
        await reload()
        return discarded
    }
}
