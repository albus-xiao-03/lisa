// Receipts for notifications this device presented: queued once, however often the system lists them again.

import Foundation
import LisaAPIContract
import LisaClient

/// Records the notifications this device presented, opened or still lists, which are the host's only evidence of
/// display (NOTIFY-05). Notifications whose receipt already waits in the offline queue are skipped, so a device that
/// stays offline does not queue the same receipts at every launch. Receipts belong to a paired device; the Mac's
/// embedded host records its own local notifications instead.
public struct NotificationReceiptRecorder: Sendable {
    /// Queues the receipts and submits them.
    public let handler: NotificationActionHandler

    /// A recorder that queues receipts through `handler`.
    public init(handler: NotificationActionHandler) {
        self.handler = handler
    }

    /// Queues receipts for the notifications among `notificationIDs` that no waiting receipt covers yet, then tries to
    /// send them within `timeLimit` when one is given.
    ///
    /// - Returns: the identifiers queued now; empty when every one was already waiting or the queue refused them.
    @discardableResult
    public func record(_ notificationIDs: [String], timeLimit: Duration? = nil) async -> [String] {
        var known: Set<String> = []
        for entry in await handler.queue.pendingEntries where entry.kind == .notificationReceipts {
            guard case .notificationReceipts(let request)? = try? entry.mutation() else { continue }
            known.formUnion(request.notificationIDs)
        }
        let fresh = notificationIDs.filter { !$0.isEmpty && known.insert($0).inserted }
        guard !fresh.isEmpty, (try? await handler.recordReceipts(fresh, timeLimit: timeLimit)) != nil else { return [] }
        return fresh
    }
}
