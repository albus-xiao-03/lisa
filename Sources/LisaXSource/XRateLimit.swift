// Reads X's rate-limit headers (x-rate-limit-limit, -remaining, -reset) into the time requests may resume.

import Foundation
import LisaHTTP

/// X's per-endpoint rate-limit state as reported on every response: `x-rate-limit-limit`, `x-rate-limit-remaining`
/// and `x-rate-limit-reset`, the "Unix timestamp when window resets"
/// (https://docs.x.com/x-api/fundamentals/rate-limits.md). With an app-only bearer token the limits are per app.
struct XRateLimitHeaders: Hashable, Sendable {
    /// Requests remaining in the current window.
    var remaining: Int?
    /// When the current window resets.
    var reset: Date?

    /// X's windows are 15 minutes or 24 hours, so a reset further away than this is clamped.
    static let maxDelaySeconds: TimeInterval = 86_400

    init(remaining: Int? = nil, reset: Date? = nil) {
        self.remaining = remaining
        self.reset = reset
    }

    init(_ response: HTTPResponse) {
        remaining = response.header("x-rate-limit-remaining").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        reset = response.header("x-rate-limit-reset").flatMap(Self.epochDate)
    }

    /// When requests may resume after a successful response that used up the window, or nil while requests remain.
    func exhaustedUntil(now: Date) -> Date? {
        guard let remaining, remaining <= 0, let reset else { return nil }
        return Self.clamped(reset, now: now)
    }

    /// When a request may be retried after HTTP 429: the window's reset, or a `Retry-After` value if X sends one,
    /// whichever is later. Nil when the response says neither; the runtime then backs off on its own schedule.
    static func retryDate(for response: HTTPResponse, now: Date) -> Date? {
        let reset = XRateLimitHeaders(response).reset.map { clamped($0, now: now) }
        let retryAfter = RetryAfter.date(in: response, now: now).map { clamped($0, now: now) }
        switch (reset, retryAfter) {
        case (let reset?, let retryAfter?): return max(reset, retryAfter)
        case (let reset?, nil): return reset
        case (nil, let retryAfter?): return retryAfter
        case (nil, nil): return nil
        }
    }

    /// Seconds since 1970, as digits with an optional fraction; anything else is ignored.
    static func epochDate(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.count <= 20,
            value.utf8.allSatisfy({ (0x30...0x39).contains($0) || $0 == 0x2E }),
            let seconds = Double(value), seconds.isFinite
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// `date`, but never earlier than `now` and never more than `maxDelaySeconds` after it.
    static func clamped(_ date: Date, now: Date) -> Date {
        min(max(date, now), now.addingTimeInterval(maxDelaySeconds))
    }
}
