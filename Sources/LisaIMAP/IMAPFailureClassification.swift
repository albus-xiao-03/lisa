// Maps everything that can end a pass to SourceErrorClass (INGEST-01 retry classification): libcurl's connection and
// login failures, lost connections and timeouts, malformed responses, and NO or BAD answers to Lisa's commands.

import LisaCurl
import LisaDomain
import LisaRedaction

/// Classifies failures honestly: retryable classes only where a later attempt can succeed without the owner.
enum IMAPFailureClassification {
    /// A failure of libcurl's connection phase: TLS, STARTTLS, address checks and login, before the hand-over.
    static func connectFailure(_ failure: CurlMailFailure, passTimedOut: Bool) -> IMAPPassFailure {
        switch failure {
        case .cancelled:
            return .cancelled
        case .refused(let reason):
            return .failed(.configuration, "the connection was refused before it was opened: \(reason)")
        case .notConnected(let reason):
            return .failed(.network, "the IMAP server could not be reached: \(reason)")
        case .untrustedServer(let reason):
            return .failed(
                .authentication,
                "the IMAP server's certificate or name could not be verified, so the connection was closed before "
                    + "login: \(reason)")
        case .startTLSUnavailable:
            return .failed(
                .capabilityDenied,
                "the IMAP server did not complete the required STARTTLS upgrade, so the connection was closed before "
                    + "login")
        case .authenticationFailed:
            return .failed(.authentication, "the IMAP server rejected the mailbox credentials")
        case .connectionLost(let reason) where passTimedOut || reason.hasPrefix("timed out"):
            return .failed(.timeout, "connecting and logging in to the IMAP server timed out")
        case .connectionLost(let reason):
            return .failed(.network, "the connection to the IMAP server was lost while logging in: \(reason)")
        case .protocolError(let reason):
            return .failed(.parse, "the IMAP server's greeting or login replies were not valid IMAP: \(reason)")
        case .serverRefused(_, let reason), .uncertain(let reason):
            return .failed(.network, "the IMAP connection failed: \(reason)")
        }
    }

    /// A failure while sending or receiving during `command`. `timeout` names the limit that was reached, if any;
    /// `midLiteral` tells whether a message was being received.
    static func streamFailure(
        _ failure: CurlMailFailure, during command: IMAPCommand, timeout: IMAPTimeoutCause?, timing: IMAPPassTiming,
        midLiteral: Bool
    ) -> IMAPPassFailure {
        if case .cancelled = failure { return .cancelled }
        switch timeout {
        case .command:
            return .failed(
                .timeout, "the IMAP server did not answer \(command.name) within \(timing.commandSeconds) seconds")
        case .pass:
            return .failed(
                .timeout, "the pass reached its limit of \(timing.passSeconds) seconds during \(command.name)")
        case nil:
            break
        }
        if midLiteral {
            return .failed(.network, "the connection was lost while a message was being received (\(command.name))")
        }
        return .failed(.network, "the connection to the IMAP server was lost during \(command.name): \(failure)")
    }

    /// A response that could not be accepted. Malformed or oversized responses are not retried automatically.
    static func protocolFailure(_ error: IMAPProtocolError, during command: IMAPCommand) -> IMAPPassFailure {
        .failed(.parse, "\(error) (during \(command.name))")
    }

    /// A tagged NO or BAD for `command`. Response codes (RFC 5530) decide whether a retry can help.
    static func refused(_ command: IMAPCommand, _ completion: IMAPCompletion, secret: Sensitive<String>)
        -> IMAPPassFailure
    {
        let name = completion.text.code?.name
        let errorClass: SourceErrorClass
        let summary: String
        if completion.status == .bad {
            errorClass = .unsupported
            summary = "the IMAP server rejected Lisa's \(command.name) command as invalid"
        } else {
            switch name {
            case "UNAVAILABLE", "INUSE", "SERVERBUG", "EXPUNGEISSUED":
                errorClass = .network
            case "LIMIT":
                errorClass = .rateLimited
            case "AUTHORIZATIONFAILED", "NOPERM", "EXPIRED", "CONTACTADMIN", "PRIVACYREQUIRED":
                errorClass = .permissionDenied
            default:
                if case .examine = command { errorClass = .configuration } else { errorClass = .partial }
            }
            switch command {
            case .examine: summary = "the IMAP server could not open the configured folder"
            case .uidSearch: summary = "the IMAP server could not search the folder"
            case .uidFetchSizes, .uidFetchMessages: summary = "the IMAP server could not return the messages"
            case .logout: summary = "the IMAP server refused LOGOUT"
            }
        }
        let description = IMAPServerText.describe(
            summary, code: completion.text.code, text: completion.text.text, withholdingIfContains: secret)
        return .failed(errorClass, description)
    }
}
