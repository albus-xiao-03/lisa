// The only commands Lisa sends after libcurl's authenticated hand-over (plan §7.3 check 1): EXAMINE, UID SEARCH, two
// forms of UID FETCH and a final LOGOUT, none of which can change the mailbox.

/// A command Lisa may send. The set is closed: there is no case for SELECT, STORE, EXPUNGE, COPY, MOVE or APPEND,
/// and no FETCH item that sets `\Seen`. EXAMINE opens the folder read-only, and `BODY.PEEK[]` "does not implicitly
/// set the \Seen flag" (RFC 9051 §6.3.3, §6.4.5).
enum IMAPCommand: Hashable, Sendable {
    /// Opens the folder read-only.
    case examine(IMAPMailboxName)
    /// `UID SEARCH UID <range>`: the UIDs present in a range.
    case uidSearch(IMAPSearchRange)
    /// `UID FETCH <set> (UID RFC822.SIZE)`: sizes only, so a pass is planned before any message is transferred.
    case uidFetchSizes(IMAPUIDSet)
    /// `UID FETCH <set> (UID RFC822.SIZE BODY.PEEK[])`: whole messages, without setting `\Seen`.
    case uidFetchMessages(IMAPUIDSet)
    /// Ends the session (RFC 9051 §6.1.3). libcurl 8.14.1 sends no LOGOUT when it cleans up a connect-only session,
    /// so Lisa sends its own.
    case logout

    /// The command as sent: tag, text and CRLF.
    func line(tag: String) -> [UInt8] { Array("\(tag) \(text)\r\n".utf8) }

    /// The command without its tag. It contains no CR, LF or literal: mailbox names are printable ASCII and every
    /// other argument is a number.
    var text: String {
        switch self {
        case .examine(let mailbox): "EXAMINE \(mailbox.quoted)"
        case .uidSearch(let range): "UID SEARCH UID \(range.commandText)"
        case .uidFetchSizes(let set): "UID FETCH \(set.commandText) (UID RFC822.SIZE)"
        case .uidFetchMessages(let set): "UID FETCH \(set.commandText) (UID RFC822.SIZE BODY.PEEK[])"
        case .logout: "LOGOUT"
        }
    }

    /// The command name, for descriptions.
    var name: String {
        switch self {
        case .examine: "EXAMINE"
        case .uidSearch: "UID SEARCH"
        case .uidFetchSizes, .uidFetchMessages: "UID FETCH"
        case .logout: "LOGOUT"
        }
    }
}
