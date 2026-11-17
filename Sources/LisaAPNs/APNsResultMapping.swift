// Maps APNs outcomes to the outbox's TransportResult: accepted, retry allowed (not sent or throttled), never retried
// (rejected), or possibly delivered (unknown, never resent automatically) (plan §6.4).

import Foundation
import LisaHTTP
import LisaPorts

/// Result mapping. Reasons name statuses, documented reason strings and failure kinds, never tokens or keys.
public enum APNsResultMapping {
    /// The result of an exchange that failed. Nothing sent → `notSent` (the outbox may retry); possibly sent →
    /// `unknown` (never resent automatically); a transport that cannot send HTTP/2-only requests → a capability
    /// rejection, never a degraded success.
    public static func result(for failure: HTTPFailure) -> TransportResult {
        switch failure {
        case .unsupported(let reason):
            return .rejected(
                reason: "capability: the HTTP transport cannot send HTTP/2-only requests (\(reason))",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .http2Unavailable:
            return .notSent(reason: "the APNs server did not negotiate HTTP/2, so nothing was sent")
        default:
            if failure.requestMayHaveBeenSent {
                return .unknown(reason: "\(failure); APNs may have received the notification")
            }
            return .notSent(reason: failure.description)
        }
    }

    /// The result of a classified response. `tokenUpdateAllowedAt` is when a newer provider token may next be used
    /// on the connection; it sets the retry time after `TooManyProviderTokenUpdates`.
    ///
    /// TransportResult has no case for a temporary provider failure with a retry time, so 5xx responses map to
    /// `throttled` with Apple's 15-minute minimum delay.
    public static func result(for response: APNsResponseClass, tokenUpdateAllowedAt: Date, now: Date)
        -> TransportResult
    {
        switch response {
        case .accepted(let apnsID):
            return .accepted(providerReference: apnsID)
        case .expiredProviderToken:
            return .rejected(
                reason: "APNs 403 ExpiredProviderToken even with a newly signed provider token; check the host clock "
                    + "and the APNs key; not retried",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .tooManyProviderTokenUpdates:
            return .throttled(retryAfter: max(tokenUpdateAllowedAt, now))
        case .deviceTokenRejected(let status, let reason, let timestamp):
            return .rejected(
                reason: "APNs \(status) \(reason): the device token is no longer valid for this topic",
                invalidatesRecipient: true, providerTimestamp: timestamp)
        case .configurationRejected(let status, let reason):
            return .rejected(
                reason: "APNs \(status) \(reason): a provider authentication or configuration problem; not retried",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .requestRejected(let status, let reason):
            return .rejected(
                reason: "APNs \(status) \(reason): the request was refused, which indicates a defect in Lisa; "
                    + "not retried",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .notAccepted(let status, let reason):
            return .notSent(reason: "APNs \(status) \(reason): the notification was not accepted; it may be retried")
        case .throttled(let retryAfter):
            return .throttled(retryAfter: retryAfter)
        case .temporaryFailure(_, _, let retryAfter):
            return .throttled(retryAfter: retryAfter)
        case .notHTTP2(let version):
            return .rejected(
                reason: "capability: the APNs response used \(version.rawValue) instead of HTTP/2",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .uncertain(let status):
            return .unknown(
                reason: "APNs answered with the undocumented status \(status); the notification may have been accepted")
        }
    }
}
