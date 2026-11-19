// Flushing the offline queue: entries go in order with their original request IDs, and each answer updates its entry.

import Foundation
import LisaAPIContract

extension OfflineQueue {
    /// The longest wait the queue accepts from a host's `retryAfterSeconds`.
    static let longestHostDelay: TimeInterval = 86_400

    /// Sends pending entries in order, each with its original request ID, so the host never applies one twice.
    ///
    /// - Applied (2xx): the entry is `done`, with the response kept for the UI until it is pruned.
    /// - Conflict (409): the entry is a `conflict` with the host's message and current revision; the flush goes on.
    /// - Throttled or unavailable (429 or 503, or 502 or 504 from a proxy): the entry stays pending with a next-attempt
    ///   time from `retryAfterSeconds`, or a doubling delay; the flush stops.
    /// - Any other refusal (other 4xx, 500): the entry is `failed` with the host's message; the flush goes on.
    /// - Unreachable or interrupted transport, cancellation, a missing or rejected credential (401), or an
    ///   unsupported API version: the entry and the rest stay pending; the flush stops.
    /// - An entry that may have been applied by an attempt longer ago than the configured retry period fails instead
    ///   of being sent, because the host may no longer recognize its request ID.
    ///
    /// Entries queued while a flush runs are sent by that flush. Calling `flush` while another flush runs returns at
    /// once with `FlushReport.Stop.alreadyRunning`.
    public func flush(using client: LisaAPIClient) async -> FlushReport {
        guard !isFlushing else { return FlushReport(stop: .alreadyRunning, remaining: awaitingCount) }
        isFlushing = true
        defer { isFlushing = false }
        var report = FlushReport(stop: .finished, remaining: 0)
        var pruned = entries
        pruneCompleted(&pruned, now: clock())
        if pruned.count != entries.count, (try? storage.save(pruned)) != nil {
            entries = pruned
        }
        var attempted: Set<String> = []
        while true {
            if Task.isCancelled {
                report.stop = .stopped(.cancelled)
                break
            }
            guard
                let next = entries.first(where: { $0.status == .pending && !attempted.contains($0.requestID) })
            else { break }
            attempted.insert(next.requestID)
            guard let stop = await process(next, using: client, report: &report) else { continue }
            report.stop = stop
            break
        }
        report.remaining = awaitingCount
        return report
    }

    /// Flushes like `flush(using:)` but gives up after `timeLimit`: the send in progress is cancelled and the remaining
    /// entries stay pending. The limit holds when the transport stops promptly on cancellation, as URLSession does.
    public nonisolated func flush(using client: LisaAPIClient, timeLimit: Duration) async -> FlushReport {
        await withTaskGroup(of: FlushReport?.self) { group in
            group.addTask { await self.flush(using: client) }
            group.addTask {
                try? await Task.sleep(for: timeLimit)
                return nil
            }
            var report: FlushReport?
            while let result = await group.next() {
                if let finished = result { report = finished }
                group.cancelAll()
            }
            return report ?? FlushReport(stop: .stopped(.cancelled), remaining: 0)
        }
    }

    /// Sends one entry and records the answer. Returns why the flush must stop, or `nil` to go on.
    private func process(
        _ entry: QueuedRequest, using client: LisaAPIClient, report: inout FlushReport
    ) async -> FlushReport.Stop? {
        let attemptedAt = clock()
        if let since = entry.uncertainSince, attemptedAt >= since.addingTimeInterval(configuration.maximumRetryPeriod) {
            var expired = entry
            expired.status = .failed
            expired.nextAttemptAt = nil
            expired.lastError = QueueEntryError(message: Self.expiryMessage)
            if let failure = commit(expired, keepOnFailure: false) { return failure }
            report.failed.append(entry.id)
            return nil
        }
        if let notBefore = entry.nextAttemptAt, notBefore > attemptedAt {
            return .deferred(until: notBefore)
        }
        var sending = entry
        sending.status = .sending
        sending.attempts += 1
        sending.lastAttemptAt = attemptedAt
        if let failure = commit(sending, keepOnFailure: false) { return failure }

        let result = await send(sending, using: client)

        guard var answered = entries.first(where: { $0.id == entry.id }) else { return nil }
        let answeredAt = clock()
        var stop: FlushReport.Stop?
        switch QueueSendOutcome.classify(result) {
        case .applied(let response):
            answered.status = .done
            answered.response = response
            answered.completedAt = answeredAt
            answered.lastError = nil
            answered.nextAttemptAt = nil
            answered.serverRevision = nil
            report.applied.append(entry.id)
        case .conflict(let error, let serverRevision):
            answered.status = .conflict
            answered.lastError = error
            answered.serverRevision = serverRevision
            answered.nextAttemptAt = nil
            report.conflicts.append(entry.id)
        case .failed(let error):
            answered.status = .failed
            answered.lastError = error
            answered.nextAttemptAt = nil
            report.failed.append(entry.id)
        case .retryLater(let error, let hostDelay):
            let notBefore = answeredAt.addingTimeInterval(retryDelay(hostDelay: hostDelay, attempts: answered.attempts))
            answered.status = .pending
            answered.lastError = error
            answered.nextAttemptAt = notBefore
            stop = .deferred(until: notBefore)
        case .interrupted(let error, let mayHaveBeenApplied, let cause):
            answered.status = .pending
            answered.lastError = error
            if mayHaveBeenApplied, answered.uncertainSince == nil { answered.uncertainSince = attemptedAt }
            stop = .stopped(cause)
        }
        // The answer already happened on the host, so it is kept in memory even when it cannot be saved; loading the
        // queue later recovers the entry as pending, and resending it with the same request ID is safe.
        if let failure = commit(answered, keepOnFailure: true) { return failure }
        return stop
    }

    /// Sends a queued entry exactly as it was queued.
    private func send(_ entry: QueuedRequest, using client: LisaAPIClient) async -> Result<APIResponse, ClientError> {
        do throws(ClientError) {
            let response = try await client.send(
                method: entry.method, path: entry.path, query: [:], body: entry.body, requestID: entry.requestID,
                authentication: .deviceCredential)
            return .success(response)
        } catch {
            return .failure(error)
        }
    }

    /// Replaces an entry and saves the queue. Returns the stop reason when the queue cannot be saved; with
    /// `keepOnFailure`, the change is kept in memory anyway.
    private func commit(_ entry: QueuedRequest, keepOnFailure: Bool) -> FlushReport.Stop? {
        var updated = entries
        guard let index = updated.firstIndex(where: { $0.id == entry.id }) else { return nil }
        updated[index] = entry
        do {
            try storage.save(updated)
            entries = updated
            return nil
        } catch {
            if keepOnFailure { entries = updated }
            return .storageFailure(String(describing: error))
        }
    }

    /// The wait before the next attempt: the host's `retryAfterSeconds` when it gave one, otherwise a delay that
    /// doubles with every attempt.
    func retryDelay(hostDelay: Int?, attempts: Int) -> TimeInterval {
        if let hostDelay { return min(max(1, TimeInterval(hostDelay)), Self.longestHostDelay) }
        let doublings = Double(min(max(0, attempts - 1), 30))
        return min(configuration.initialRetryDelay * pow(2, doublings), configuration.maximumRetryDelay)
    }

    private static let expiryMessage =
        "an earlier attempt may have been applied and its retry period has ended, so sending it again could apply it "
        + "twice; check the item before submitting it again"
}
