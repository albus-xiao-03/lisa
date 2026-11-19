// Backoff with jitter for failing source jobs (OPS-01), honoring a provider's retry-after time.

import Foundation

/// Computes when a failing job runs next.
public struct RetrySchedule: Hashable, Sendable {
    public var baseSeconds: Double
    public var maxSeconds: Double

    public init(baseSeconds: Double = 60, maxSeconds: Double = 3_600) {
        self.baseSeconds = baseSeconds
        self.maxSeconds = maxSeconds
    }

    /// The delay after `failures` consecutive failures: exponential, capped, with jitter in [0.5, 1.0] of the value.
    /// `random` is in [0, 1) so tests can fix it.
    public func delay(afterFailures failures: Int, random: Double) -> TimeInterval {
        let exponent = Double(min(max(0, failures - 1), 16))
        let raw = min(maxSeconds, baseSeconds * pow(2, exponent))
        return raw * (0.5 + 0.5 * min(max(random, 0), 1))
    }

    /// The next run time, never earlier than `retryAfter`.
    public func nextRun(after now: Date, failures: Int, retryAfter: Date?, random: Double) -> Date {
        let candidate = now.addingTimeInterval(delay(afterFailures: failures, random: random))
        guard let retryAfter else { return candidate }
        return max(candidate, retryAfter)
    }
}
