// Why a server's IMAP response could not be accepted: framing, size and syntax failures found while reading the
// small response subset Lisa understands.

/// A malformed, oversized or unexpected server response. Descriptions are written by Lisa and never quote server
/// data, so they are safe to log and to store as a source failure.
enum IMAPProtocolError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The text of one response (literal data excluded) exceeded the limit.
    case lineTooLong(limit: Int)
    /// A literal announced more octets than this command accepts.
    case literalTooLarge(declared: UInt64, limit: Int)
    /// The literals received for this command exceed what it may receive in total.
    case literalBudgetExceeded(limit: Int)
    /// One response carried more literals than allowed.
    case tooManyLiterals(limit: Int)
    /// A line was not ended by CRLF, or contained NUL or a bare CR.
    case malformedLine(String)
    /// The server sent a non-synchronizing literal, which servers must not send (RFC 9051 §4.3).
    case nonSynchronizingLiteral
    /// The response did not follow the IMAP grammar.
    case malformedResponse(String)
    /// The response is valid IMAP but not one any of Lisa's commands asks for.
    case unexpectedResponse(String)

    var description: String {
        switch self {
        case .lineTooLong(let limit): "a server response line exceeded \(limit) bytes"
        case .literalTooLarge(let declared, let limit):
            "the server announced a literal of \(declared) bytes, more than the \(limit) bytes allowed"
        case .literalBudgetExceeded(let limit): "the server sent more than the \(limit) bytes allowed for this command"
        case .tooManyLiterals(let limit): "a server response contained more than \(limit) literals"
        case .malformedLine(let reason): "a server response line was malformed: \(reason)"
        case .nonSynchronizingLiteral: "the server sent a non-synchronizing literal, which servers must not send"
        case .malformedResponse(let reason): "a server response was malformed: \(reason)"
        case .unexpectedResponse(let reason): "the server sent an unexpected response: \(reason)"
        }
    }
}
