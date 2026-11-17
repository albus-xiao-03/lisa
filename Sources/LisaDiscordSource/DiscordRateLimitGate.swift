// Remembers until when Discord's rate limit for this channel's route is used up, so nothing is sent before then.

import Foundation
import LisaPorts
import Synchronization

/// The connector's view of its rate limit, kept in memory for the life of the connector. Discord counts 429 responses
/// toward its invalid-request limit ("10,000 per 10 minutes", after which the IP address is temporarily restricted),
/// so a request that would only be refused is not made
/// (https://docs.discord.com/developers/topics/rate-limits.md#invalid-request-limit-aka-cloudflare-bans).
final class DiscordRateLimitGate: Sendable {
    private let blockedUntil = Mutex<Date?>(nil)

    init() {}

    /// Throws a rate-limit failure while the bucket is used up.
    func check(now: Date) throws(ConnectorError) {
        let until = blockedUntil.withLock { $0 }
        guard let until, until > now else { return }
        throw ConnectorError(
            .rateLimited, "Discord's rate limit for this channel is used up; reading resumes when it resets",
            retryAfter: until)
    }

    /// Records when the bucket refills; nil leaves the current state unchanged.
    func block(until date: Date?) {
        guard let date else { return }
        blockedUntil.withLock { current in
            if current.map({ date > $0 }) ?? true { current = date }
        }
    }
}
