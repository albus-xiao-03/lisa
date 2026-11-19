// Submitting an action as every model does: durably queued with a stable request ID, then a bounded attempt to send.

import Foundation
import LisaAPIContract
import LisaClient

/// Submits the models' mutations (UI-03, NOTIFY-05).
///
/// 1. When the device must be paired and is not, the outcome is `.unavailable` and nothing is queued.
/// 2. The mutation is written to the offline queue, which gives it its stable request ID. With coalescing, a queued
///    change of the same subject that the host cannot have applied is merged into it first (`MutationCoalescing`).
/// 3. The queue is flushed, earlier entries first, for at most the context's time limit. The entry's state afterwards
///    is the outcome: done, still queued, a recoverable conflict, or a failure. The failure of an action just taken is
///    reported to the owner as its outcome, so its entry is removed instead of being left among the pending actions.
/// 4. When the queue refuses the mutation (full, or its storage failed), it is sent once directly; when the host
///    cannot be reached then, the outcome is `.unavailable` because nothing could be saved.
struct ActionSubmitter: Sendable {
    /// What one submission did.
    struct Submission: Sendable {
        /// The truthful result.
        var outcome: ActionOutcome
        /// The queued entry as it stands afterwards; `nil` when nothing was queued.
        var entry: QueuedRequest?
        /// The host's success response as JSON, when the host applied the action.
        var responseBody: Data?
        /// What the attempt showed about the connection.
        var contact: HostContact?

        init(
            outcome: ActionOutcome, entry: QueuedRequest? = nil, responseBody: Data? = nil, contact: HostContact? = nil
        ) {
            self.outcome = outcome
            self.entry = entry
            self.responseBody = responseBody
            self.contact = contact
        }

        /// The success response decoded as `type`, or `nil` when there is none or it does not decode.
        func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
            guard let responseBody, !responseBody.isEmpty else { return nil }
            return try? APIJSON.decoder().decode(type, from: responseBody)
        }
    }

    let context: ClientContext

    /// Queues `mutation` and tries to send it now.
    func submit(_ mutation: QueuedMutation, coalescing: Bool = false) async -> Submission {
        if let refusal = await pairingRefusal() { return refusal }
        let replacement = coalescing ? await mergeableEntry(for: mutation) : nil
        let queued: QueuedRequest
        do {
            queued = try await context.queue.enqueue(replacement?.merged ?? mutation)
        } catch let error as OfflineQueueError {
            switch error {
            case .full: return await sendDirectly(mutation, queueProblem: error.description)
            default: return Submission(outcome: .failed(reason: error.description))
            }
        } catch {
            return await sendDirectly(mutation, queueProblem: "the offline queue could not be saved")
        }
        if let replacement {
            // The merged entry holds the earlier change too. Should the earlier one be sent meanwhile, it stays; the
            // merged one then expects an outdated revision and is a recoverable conflict, never a second application.
            try? await context.queue.discard(replacement.entryID)
        }
        return await attempt(queued.id, discardingFailure: true)
    }

    /// Makes a conflicting or failed entry pending again as a new request, expecting `expectedRevision` when the
    /// mutation carries one, and tries to send it now. A failure stays in the queue for the owner to resolve.
    func resubmit(_ entryID: String, expectedRevision: Int64?) async -> Submission {
        if let refusal = await pairingRefusal() { return refusal }
        do {
            try await requeue(entryID, expectedRevision: expectedRevision)
        } catch {
            return Submission(outcome: .failed(reason: String(describing: error)))
        }
        return await attempt(entryID, discardingFailure: false)
    }

    // MARK: - Steps

    /// The submission refused because the device is not paired, or `nil` when it may go ahead.
    private func pairingRefusal() async -> Submission? {
        guard context.requiresPairing else { return nil }
        do throws(ClientError) {
            guard try await context.client.installation().isPaired else {
                return Submission(outcome: .unavailable(reason: ActionOutcome.notPairedReason), contact: .notPaired)
            }
            return nil
        } catch {
            return Submission(outcome: .failed(reason: error.description))
        }
    }

    /// Flushes the queue for at most the time limit and reports the entry's state afterwards.
    private func attempt(_ id: String, discardingFailure: Bool) async -> Submission {
        let report = await context.queue.flush(using: context.client, timeLimit: context.submitTimeLimit)
        let contact = HostContact(report)
        guard let entry = await context.queue.entry(id) else {
            return Submission(outcome: .failed(reason: "the queued action is no longer in the queue"), contact: contact)
        }
        if discardingFailure, entry.status == .failed {
            try? await context.queue.discard(entry.id)
        }
        return Submission(
            outcome: ActionOutcome(entry), entry: entry, responseBody: entry.response?.body, contact: contact)
    }

    /// Sends a mutation the queue refused once, directly.
    private func sendDirectly(_ mutation: QueuedMutation, queueProblem: String) async -> Submission {
        do throws(ClientError) {
            let body = try await DirectMutationSender.send(mutation, using: context.client)
            return Submission(outcome: .done, responseBody: body, contact: .reached)
        } catch {
            var outcome = ActionOutcome(unqueuedFailure: error)
            if case .unavailable(let reason) = outcome { outcome = .unavailable(reason: "\(queueProblem); \(reason)") }
            return Submission(outcome: outcome, contact: HostContact(error))
        }
    }

    /// Re-queues an entry, falling back to a plain retry when its mutation has no expected revision to replace.
    private func requeue(_ entryID: String, expectedRevision: Int64?) async throws {
        do {
            _ = try await context.queue.requeue(entryID, expectedRevision: expectedRevision)
        } catch let error as OfflineQueueError {
            guard case .revisionNotApplicable = error else { throw error }
            _ = try await context.queue.requeue(entryID)
        }
    }

    /// The latest queued entry of the same subject and `mutation` merged into it, when the host cannot have applied
    /// that entry: it is pending and no attempt of it ended without a definite answer (`uncertainSince` is unset), so
    /// every attempt failed before reaching the host or was refused. `nil` otherwise. The caller queues the merged
    /// mutation first and discards the entry afterwards, so a failure in between loses no change.
    private func mergeableEntry(for mutation: QueuedMutation) async -> (entryID: String, merged: QueuedMutation)? {
        let route = mutation.route
        guard
            let latest = await context.queue.pendingEntries.last(where: {
                $0.method == route.method && $0.path == route.path
            }),
            latest.status == .pending, latest.uncertainSince == nil, let earlier = try? latest.mutation(),
            let merged = MutationCoalescing.merge(earlier, mutation)
        else { return nil }
        return (latest.id, merged)
    }
}
