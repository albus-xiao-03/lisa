// Which UIDs one UID SEARCH asks for: bounded windows below the folder's UIDNEXT, so a result never grows with the
// mailbox, and a final open-ended window whose `*` also covers messages above a stale UIDNEXT (RFC 9051 §6.4.9).

/// The UID range of one UID SEARCH: `lower:upper`, or `lower:*` for the final window.
struct IMAPSearchRange: Hashable, Sendable {
    let lower: UInt32
    /// nil for `*`, the highest UID in use.
    let upper: UInt32?

    var commandText: String { upper.map { "\(lower):\($0)" } ?? "\(lower):*" }

    var isFinal: Bool { upper == nil }
}

/// Chooses search windows.
enum IMAPSearchWindows {
    /// The most UIDs a bounded window spans, which keeps an IMAP4rev1 SEARCH result near 110 KB.
    static let span: UInt32 = 10_000
    /// Bounded windows searched in one pass; after that the pass returns its progress and asks for another.
    static let maxRounds = 20

    /// The window starting at `lower`. While more than `span` UIDs lie below UIDNEXT, the window is bounded.
    /// Otherwise it is `lower:*`, which always includes the highest UID even when that is below `lower`
    /// (RFC 9051 §6.4.9), so its results must be filtered to UIDs ≥ `lower`.
    static func range(from lower: UInt32, uidNext: UInt32?, span: UInt32 = span) -> IMAPSearchRange {
        if let uidNext, span > 0, uidNext > lower, uidNext - lower > span {
            return IMAPSearchRange(lower: lower, upper: lower + (span - 1))
        }
        return IMAPSearchRange(lower: lower, upper: nil)
    }
}
