// The typed form of the IMAP responses Lisa reads (RFC 9051 §7): tagged and untagged status, CAPABILITY, EXISTS,
// SEARCH and ESEARCH results, FETCH data and BYE. Anything else is recognized only enough to be ignored.

import Foundation

/// The result of a command or an untagged status (RFC 9051 §7.1).
enum IMAPStatus: Hashable, Sendable {
    case ok
    case no
    case bad
}

/// A bracketed response code (RFC 9051 §7.1). Codes Lisa does not act on keep only their name; RFC 9051 requires
/// clients to ignore codes they do not recognize.
enum IMAPResponseCode: Hashable, Sendable {
    case readOnly
    case readWrite
    case uidValidity(UInt32)
    case uidNext(UInt32)
    case capability([String])
    /// Any other code by its uppercased name, such as `NONEXISTENT` or `UNAVAILABLE` (RFC 5530).
    case other(String)

    var name: String {
        switch self {
        case .readOnly: "READ-ONLY"
        case .readWrite: "READ-WRITE"
        case .uidValidity: "UIDVALIDITY"
        case .uidNext: "UIDNEXT"
        case .capability: "CAPABILITY"
        case .other(let name): name
        }
    }
}

/// The text part of a status response: an optional code and the human-readable text, which comes from the server
/// and is untrusted.
struct IMAPStatusText: Hashable, Sendable {
    var code: IMAPResponseCode?
    var text: [UInt8]

    init(code: IMAPResponseCode? = nil, text: [UInt8] = []) {
        self.code = code
        self.text = text
    }
}

/// A message's content in a FETCH response: its octets, or NIL when the server has none to give.
enum IMAPBodyContent: Hashable, Sendable {
    case octets(Data)
    case absent
}

/// The FETCH data items Lisa reads (RFC 9051 §7.5.2); other items are skipped.
struct IMAPFetchData: Hashable, Sendable {
    var uid: UInt32?
    var size: UInt64?
    /// `BODY[]`, the whole message. Other sections are skipped.
    var body: IMAPBodyContent?

    init(uid: UInt32? = nil, size: UInt64? = nil, body: IMAPBodyContent? = nil) {
        self.uid = uid
        self.size = size
        self.body = body
    }
}

/// An ESEARCH response (RFC 9051 §7.3.4). Only the UID indicator and the ALL result are used.
struct IMAPExtendedSearch: Hashable, Sendable {
    /// The tag of the command it answers, when the server names it.
    var tag: String?
    var isUID: Bool
    var all: IMAPUIDSet

    init(tag: String? = nil, isUID: Bool, all: IMAPUIDSet = IMAPUIDSet()) {
        self.tag = tag
        self.isUID = isUID
        self.all = all
    }
}

/// One parsed server response.
enum IMAPResponse: Hashable, Sendable {
    /// The completion of the command with this tag.
    case tagged(tag: String, status: IMAPStatus, IMAPStatusText)
    /// An untagged OK, NO or BAD.
    case status(IMAPStatus, IMAPStatusText)
    /// The server is closing the connection (RFC 9051 §7.1.5).
    case bye(IMAPStatusText)
    /// The connection was authenticated without credentials; valid only as a greeting.
    case preauth(IMAPStatusText)
    case capability([String])
    case exists(UInt32)
    /// An IMAP4rev1 SEARCH result; for UID SEARCH the numbers are UIDs (RFC 3501 §7.2.5).
    case search(IMAPUIDSet)
    case extendedSearch(IMAPExtendedSearch)
    case fetch(sequence: UInt32, IMAPFetchData)
    case expunge(UInt32)
    /// A command continuation request ("+"), which none of Lisa's commands asks for.
    case continuation
    /// A response Lisa does not use (FLAGS, LIST, RECENT, STATUS, ...), by its uppercased keyword.
    case ignored(String)
}
