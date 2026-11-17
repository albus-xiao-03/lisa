// Reads Discord's rate-limit headers and 429 bodies into the time requests may resume.

import Foundation
import LisaHTTP

/// Discord's rate-limit state for the route, from `X-RateLimit-Remaining`, `X-RateLimit-Reset` (epoch seconds),
/// `X-RateLimit-Reset-After` (seconds, "can have decimals"), `X-RateLimit-Scope` and `X-RateLimit-Global`
/// (https://docs.discord.com/developers/topics/rate-limits.md#header-format). Limits are read from the responses,
/// never hard-coded, as Discord asks.
struct DiscordRateLimitHeaders: Hashable, Sendable {
    var remaining: Int?
    var resetAfter: Double?
    var reset: Date?
    /// `user`, `global` or `shared`; only on 429 responses.
    var scope: String?
    var isGlobal: Bool

    /// A wait longer than this is clamped, so a malformed header cannot park the source indefinitely.
    static let maxDelaySeconds: TimeInterval = 86_400

    init(
        remaining: Int? = nil, resetAfter: Double? = nil, reset: Date? = nil, scope: String? = nil,
        isGlobal: Bool = false
    ) {
        self.remaining = remaining
        self.resetAfter = resetAfter
        self.reset = reset
        self.scope = scope
        self.isGlobal = isGlobal
    }

    init(_ response: HTTPResponse) {
        remaining = response.header("X-RateLimit-Remaining").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        resetAfter = response.header("X-RateLimit-Reset-After").flatMap(Self.seconds)
        reset = response.header("X-RateLimit-Reset").flatMap(Self.seconds).map { Date(timeIntervalSince1970: $0) }
        scope = response.header("X-RateLimit-Scope").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        isGlobal = response.header("X-RateLimit-Global")?.trimmingCharacters(in: .whitespaces).lowercased() == "true"
    }

    /// When the route's bucket refills after a successful response that used it up, or nil while requests remain.
    /// Discord asks clients not to make "requests on exhausted buckets until after they have reset".
    func exhaustedUntil(now: Date) -> Date? {
        guard let remaining, remaining <= 0 else { return nil }
        if let resetAfter { return Self.clamped(now.addingTimeInterval(resetAfter), now: now) }
        return reset.map { Self.clamped($0, now: now) }
    }

    /// When a request may be retried after HTTP 429: the latest of `Retry-After`, the body's `retry_after` and
    /// `X-RateLimit-Reset-After` ("Your application should rely on the `Retry-After` header or `retry_after` field").
    static func retryDate(for response: HTTPResponse, body: DiscordErrorBody, now: Date) -> Date? {
        let headers = DiscordRateLimitHeaders(response)
        let candidates = [
            response.header("Retry-After").flatMap(seconds).map { now.addingTimeInterval($0) },
            body.retryAfter.map { now.addingTimeInterval($0) },
            headers.resetAfter.map { now.addingTimeInterval($0) },
        ].compactMap { $0 }
        return candidates.max().map { clamped($0, now: now) }
    }

    /// Non-negative seconds as digits with an optional fraction; anything else is ignored.
    static func seconds(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.count <= 24,
            value.utf8.allSatisfy({ (0x30...0x39).contains($0) || $0 == 0x2E }),
            let seconds = Double(value), seconds.isFinite
        else { return nil }
        return seconds
    }

    /// `date`, but never earlier than `now` and never more than `maxDelaySeconds` after it.
    static func clamped(_ date: Date, now: Date) -> Date {
        min(max(date, now), now.addingTimeInterval(maxDelaySeconds))
    }
}
