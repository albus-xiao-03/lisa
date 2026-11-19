// Limits and timing of the offline queue: capacity, retention of applied entries, retry delays and the retry period.

import Foundation
import LisaAPIContract

/// Limits and timing of an `OfflineQueue` (L22: bounded).
public struct OfflineQueueConfiguration: Hashable, Sendable {
    /// The most entries the queue holds; enqueueing beyond it fails.
    public var capacity: Int
    /// The most request-body bytes the queue holds in total.
    public var maxTotalBodyBytes: Int
    /// How long applied entries stay visible, with their responses, before they are pruned.
    public var completedRetention: TimeInterval
    /// The first delay after a throttled or unavailable response that gives no `retryAfterSeconds`; it doubles with
    /// every further attempt up to `maximumRetryDelay`.
    public var initialRetryDelay: TimeInterval
    /// The longest delay the queue chooses itself. A longer `retryAfterSeconds` from the host is honored, up to a day.
    public var maximumRetryDelay: TimeInterval
    /// How long an entry whose earlier attempt may have been applied keeps being retried. It never exceeds the
    /// host's idempotency retention (`APIVersioning.idempotencyRetentionDays`): after that, a retry could apply the
    /// request a second time, so the entry fails and the owner decides.
    public var maximumRetryPeriod: TimeInterval

    /// The host's idempotency retention, in seconds.
    public static let idempotencyRetention = TimeInterval(APIVersioning.idempotencyRetentionDays) * 86_400

    /// Limits and timing. Values out of range are clamped: at least one entry, a total no smaller than one
    /// request body, delays of at least a second, and a retry period no longer than the host's idempotency
    /// retention.
    public init(
        capacity: Int = 500, maxTotalBodyBytes: Int = 8 * 1_048_576, completedRetention: TimeInterval = 3_600,
        initialRetryDelay: TimeInterval = 30, maximumRetryDelay: TimeInterval = 1_800,
        maximumRetryPeriod: TimeInterval = OfflineQueueConfiguration.idempotencyRetention
    ) {
        self.capacity = max(1, capacity)
        self.maxTotalBodyBytes = max(APIVersioning.maxRequestBytes, maxTotalBodyBytes)
        self.completedRetention = max(0, completedRetention)
        self.initialRetryDelay = max(1, initialRetryDelay)
        self.maximumRetryDelay = max(self.initialRetryDelay, maximumRetryDelay)
        self.maximumRetryPeriod = min(max(0, maximumRetryPeriod), Self.idempotencyRetention)
    }
}
