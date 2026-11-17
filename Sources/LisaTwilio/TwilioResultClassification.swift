// How a call attempt's outcome becomes a TransportResult: a created call is accepted, refusals fail, 429 is
// throttled, and anything that may have created a call is "unknown", so it is never placed again automatically.

import Foundation
import LisaHTTP
import LisaPorts
import LisaSecrets

/// Classifies call outcomes from Twilio's documented responses. The outbox retries `notSent` and
/// `temporarilyUnavailable` with backoff, retries `throttled` after the given time, fails `rejected`, and never resends
/// `unknown`. Reasons quote only HTTP statuses,
/// Twilio error codes and request IDs: exception messages can contain phone numbers and are never copied.
enum TwilioResultClassification {
    static func result(for response: HTTPResponse, now: Date) -> TransportResult {
        switch response.status {
        case 200...299:
            // 201 Created: "The response body contains the new resource"; its SID is the provider reference.
            return .accepted(providerReference: TwilioResponseBody.callSID(in: response.body))
        case 429:
            // Error 20429: "Requests that receive 429 responses aren't processed and are safe to retry after backing
            // off." Twilio documents no Retry-After for it, so one is used only if present.
            return .throttled(retryAfter: RetryAfter.date(in: response, now: now))
        case 408:
            // RFC 9110 §15.5.9: the server did not receive a complete request message, so it did not act on it.
            return .temporarilyUnavailable(
                reason: "Twilio did not receive the complete call request (HTTP 408)",
                retryAfter: RetryAfter.date(in: response, now: now))
        case 401:
            return refused("Twilio refused the account credentials" + details(response))
        case 400...499:
            // Validation errors such as an invalid number (400) and permission or resource errors: the same request
            // cannot succeed.
            return refused("Twilio refused the call request" + details(response))
        default:
            // 5xx, redirects and anything else. Twilio documents only 429 as "not processed", and creating a call
            // takes no idempotency key, so a call may already exist: placing it again could ring the owner twice.
            return .unknown(
                reason: "Twilio answered the call request" + details(response)
                    + ", so a call may have been placed; it is not placed again automatically")
        }
    }

    /// The HTTP exchange failed. Only a failure that provably left nothing sent may be retried.
    static func result(for failure: HTTPFailure) -> TransportResult {
        guard failure.requestMayHaveBeenSent else {
            return .notSent(reason: "the call request was not sent: \(failure.description)")
        }
        return .unknown(
            reason: "the call request may have reached Twilio but no answer was read (\(failure.description)), "
                + "so a call may have been placed; it is not placed again automatically")
    }

    /// The auth token could not be resolved; nothing was sent.
    static func result(forSecretError error: any Error) -> TransportResult {
        switch error as? SecretStoreError {
        case .unreadable(let reference):
            // For example a locked keychain: reading again later may succeed.
            return .notSent(reason: "the Twilio auth token \(reference) could not be read")
        case let known?:
            return refused("the Twilio auth token is not usable: \(known.description)")
        case nil:
            return refused("the Twilio auth token could not be read")
        }
    }

    /// A call that was not attempted because the settings or the request cannot work.
    static func refused(_ reason: String) -> TransportResult {
        .rejected(reason: reason, invalidatesRecipient: false, providerTimestamp: nil)
    }

    /// ` (HTTP 400, Twilio error 21211, request RQ…)`, with the parts that are present and well-formed.
    static func details(_ response: HTTPResponse) -> String {
        var parts = ["HTTP \(response.status)"]
        if let code = TwilioResponseBody.errorCode(in: response.body) { parts.append("Twilio error \(code)") }
        if let requestID = response.header("Twilio-Request-Id"), TwilioFormats.isRequestID(requestID) {
            parts.append("request \(requestID)")
        }
        return " (" + parts.joined(separator: ", ") + ")"
    }
}
