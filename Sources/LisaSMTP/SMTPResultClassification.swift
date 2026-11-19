// How an SMTP submission's outcome becomes a TransportResult the outbox can act on without sending twice: a message
// that may have been accepted is "unknown" and never resent, a permanent refusal fails, and anything that left the
// message unaccepted may be retried.

import LisaCurl
import LisaPorts
import LisaSecrets

/// Classifies outcomes. The outbox retries `notSent` and `temporarilyUnavailable` with backoff and jitter within its
/// attempt limit, fails `rejected`, and records `unknown` without ever resending it.
enum SMTPResultClassification {
    /// A submission libcurl could not complete.
    static func result(for failure: CurlMailFailure) -> TransportResult {
        switch failure {
        case .refused(let reason):
            // Before any connection: typically the host resolved only to addresses the policy forbids, which a
            // network change (a captive portal's DNS) can cause and fix.
            return .notSent(reason: "the submission was refused before connecting: \(reason)")
        case .notConnected(let reason):
            return .notSent(reason: "the mail server could not be reached: \(reason)")
        case .untrustedServer(let reason):
            // Nothing was sent, and every retry verifies the certificate again: an interception on one network
            // (such as a captive portal) cannot weaken a later attempt.
            return .notSent(
                reason: "the mail server's certificate could not be verified, so nothing was sent: \(reason)")
        case .startTLSUnavailable:
            // Only EHLO and STARTTLS were sent in clear; no credential and no message.
            return .notSent(
                reason: "the mail server did not complete the required STARTTLS upgrade, so nothing was sent")
        case .authenticationFailed(let reason):
            // Retrying refused credentials cannot succeed and invites account lockouts or address bans.
            return .rejected(
                reason: "the mail server refused the configured SMTP credentials (\(reason))",
                invalidatesRecipient: false, providerTimestamp: nil)
        case .serverRefused(let code, _) where (400...499).contains(code):
            // RFC 5321 §4.2.1: 4yz is a transient negative reply; the message was not accepted.
            return .temporarilyUnavailable(
                reason: "the mail server temporarily refused with reply \(code); nothing was accepted", retryAfter: nil)
        case .serverRefused(let code, _) where (500...599).contains(code):
            // RFC 5321 §4.2.1: 5yz is permanent; the client SHOULD NOT repeat the exact request.
            return .rejected(
                reason: "the mail server refused with reply \(code)", invalidatesRecipient: false,
                providerTimestamp: nil)
        case .serverRefused(let code, _):
            return .unknown(reason: "the mail server answered with unexpected reply \(code)")
        case .uncertain(let reason):
            return .unknown(
                reason: "the whole message was handed over but the server's reply was not received (\(reason)); "
                    + "it may have been accepted")
        case .connectionLost(let reason):
            return .notSent(reason: "the connection ended before the message was accepted: \(reason)")
        case .protocolError(let reason):
            // LisaCurl reports protocol errors only before any message data is sent.
            return .notSent(reason: "the mail server did not follow SMTP before the message was sent: \(reason)")
        case .cancelled:
            return .notSent(reason: "the submission was cancelled before any message data was sent")
        }
    }

    /// An envelope that cannot become a valid message: sending the same envelope again cannot succeed.
    static func result(for error: SMTPCompositionError) -> TransportResult {
        .rejected(
            reason: "the message was not sent: \(error.description)", invalidatesRecipient: false,
            providerTimestamp: nil)
    }

    /// The password could not be resolved; nothing was sent.
    static func result(forSecretError error: any Error, reference: SecretReference) -> TransportResult {
        guard let error = error as? SecretStoreError else {
            return .rejected(
                reason: "the SMTP password \(reference) could not be read", invalidatesRecipient: false,
                providerTimestamp: nil)
        }
        switch error {
        case .unreadable:
            // For example a locked keychain: reading again later may succeed.
            return .notSent(reason: "the SMTP password could not be read: \(error.description)")
        case .notFound, .unprotectedFile, .tooLarge, .unsupported:
            return .rejected(
                reason: "the SMTP password is not usable: \(error.description)", invalidatesRecipient: false,
                providerTimestamp: nil)
        }
    }

    /// Settings that cannot work.
    static func misconfigured(_ problems: [String]) -> TransportResult {
        .rejected(
            reason: "the SMTP transport is misconfigured: " + problems.joined(separator: "; "),
            invalidatesRecipient: false, providerTimestamp: nil)
    }
}
