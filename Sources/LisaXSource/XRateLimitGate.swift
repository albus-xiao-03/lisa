// Remembers until when X's rate-limit window is used up, so the connector sends nothing before the window resets.

import Foundation
import LisaPorts
import Synchronization

/// The connector's view of its rate-limit window, kept in memory for the life of the connector. X asks clients to
/// "wait until that time before retrying" (https://docs.x.com/x-api/fundamentals/rate-limits.md); a request made
/// earlier would only be refused.
final class XRateLimitGate: Sendable {
    private let blockedUntil = Mutex<Date?>(nil)

    init() {}

    /// Throws a rate-limit failure while the window is used up.
    func check(now: Date) throws(ConnectorError) {
        let until = blockedUntil.withLock { $0 }
        guard let until, until > now else { return }
        throw ConnectorError(
            .rateLimited, "the X rate-limit window for this app is used up; reading resumes when it resets",
            retryAfter: until)
    }

    /// Records the time the window resets; nil leaves the current state unchanged.
    func block(until date: Date?) {
        guard let date else { return }
        blockedUntil.withLock { current in
            if current.map({ date > $0 }) ?? true { current = date }
        }
    }
}
