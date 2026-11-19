// Classifies an APNs response by status code and reason string, following Apple's response documentation and
// retry rules (S13) and the plan's classification table (§6.4).

import Foundation
import LisaHTTP

/// What an APNs response means for one push, before it is mapped to a transport result.
public enum APNsResponseClass: Hashable, Sendable {
    /// 200: APNs accepted the notification, which says nothing about display. Carries the `apns-id`.
    case accepted(apnsID: String)
    /// 403 `ExpiredProviderToken`: "a new token should be generated"; the push is retried once with a new token.
    case expiredProviderToken
    /// 429 `TooManyProviderTokenUpdates`: the cached token is kept and the push waits for the 20-minute interval.
    case tooManyProviderTokenUpdates
    /// 400 `BadDeviceToken` or `DeviceTokenNotForTopic`, or any 410: the device token cannot be used for the
    /// topic. Never retried. Only a 410 carries the provider's timestamp.
    case deviceTokenRejected(status: Int, reason: String, providerTimestamp: Date?)
    /// 400 `BadTopic`, `MissingTopic` or `TopicDisallowed`, or a 403 other than an expired token: provider
    /// authentication or configuration. Never retried.
    case configurationRejected(status: Int, reason: String)
    /// Other 400s, 404, 405, 413 and undocumented error statuses: the request itself was refused, which points to a
    /// defect in Lisa. Never retried.
    case requestRejected(status: Int, reason: String)
    /// 400 `IdleTimeout`: not accepted, and not one of the errors Apple says never to retry.
    case notAccepted(status: Int, reason: String)
    /// 429 `TooManyRequests` (or another 429): retried with a delay; `retryAfter` comes from `Retry-After` if sent.
    case throttled(retryAfter: Date?)
    /// 5xx: retried no sooner than 15 minutes later (Apple), or later if `Retry-After` asks for more.
    case temporaryFailure(status: Int, reason: String, retryAfter: Date)
    /// The response did not use HTTP/2: a capability failure, never a success.
    case notHTTP2(HTTPVersion)
    /// A 2xx status other than the documented 200: APNs may have accepted the notification.
    case uncertain(status: Int)
}

/// Response classification. It is pure: the same response and instant always give the same class.
public enum APNsResponseClassifier {
    /// Apple: "After 15 minutes, you can retry JSON payloads that receive response status codes that begin with 5XX."
    public static let serverErrorRetryDelay: TimeInterval = 15 * 60

    /// Classifies `response` to a request sent with `requestAPNsID` at about `now`.
    public static func classify(_ response: HTTPResponse, requestAPNsID: String, now: Date) -> APNsResponseClass {
        guard response.version == .http2 else { return .notHTTP2(response.version) }
        let status = response.status
        if status == 200 {
            let echoed = response.header("apns-id")?.lowercased()
            let apnsID = echoed.flatMap { APNsIdentifiers.isCanonicalUUID($0) ? $0 : nil } ?? requestAPNsID
            return .accepted(apnsID: apnsID)
        }
        let body = APNsErrorBody(parsing: response.body)
        let reason = body.label
        switch status {
        case 400:
            switch body.reason {
            case .badDeviceToken, .deviceTokenNotForTopic:
                return .deviceTokenRejected(status: status, reason: reason, providerTimestamp: nil)
            case .badTopic, .missingTopic, .topicDisallowed:
                return .configurationRejected(status: status, reason: reason)
            case .idleTimeout:
                return .notAccepted(status: status, reason: reason)
            default:
                return .requestRejected(status: status, reason: reason)
            }
        case 403:
            if body.reason == .expiredProviderToken { return .expiredProviderToken }
            return .configurationRejected(status: status, reason: reason)
        case 410:
            return .deviceTokenRejected(status: status, reason: reason, providerTimestamp: body.timestamp)
        case 429:
            if body.reason == .tooManyProviderTokenUpdates { return .tooManyProviderTokenUpdates }
            return .throttled(retryAfter: RetryAfter.date(in: response, now: now))
        case 500...599:
            let earliest = now.addingTimeInterval(serverErrorRetryDelay)
            let requested = RetryAfter.date(in: response, now: now)
            return .temporaryFailure(
                status: status, reason: reason, retryAfter: requested.map { max($0, earliest) } ?? earliest)
        case 201...299:
            return .uncertain(status: status)
        default:
            return .requestRejected(status: status, reason: reason)
        }
    }
}
