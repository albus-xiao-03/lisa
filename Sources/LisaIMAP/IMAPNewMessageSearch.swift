// Finds the UIDs above the cursor with UID SEARCH over bounded windows (RFC 9051 §6.4.4, §6.4.9), accepting the
// IMAP4rev1 SEARCH and the IMAP4rev2 ESEARCH forms of the result.

import LisaRedaction

/// The new messages found for one pass.
struct IMAPNewMessages: Hashable, Sendable {
    /// UIDs above the cursor, ascending.
    var candidates: [UInt32]
    /// Whether more messages may exist beyond the candidates.
    var hasMore: Bool
    /// The end of the last bounded window that held no message: UIDs up to it are below UIDNEXT and absent, so no
    /// message can ever have them (RFC 9051 §2.3.1.1), and the cursor may move past them.
    var emptyThrough: UInt32?
}

/// Windowed UID SEARCH.
enum IMAPNewMessageSearch {
    /// Searches from `last + 1` for at most `limit` UIDs whose set fits in one command. `last` must be below
    /// `UInt32.max`.
    static func find(
        above last: UInt32, uidNext: UInt32?, limit: Int, channel: IMAPCommandChannel, secret: Sensitive<String>
    ) throws(IMAPPassFailure) -> IMAPNewMessages {
        var lower = last + 1
        var emptyThrough: UInt32?
        for _ in 0..<IMAPSearchWindows.maxRounds {
            let range = IMAPSearchWindows.range(from: lower, uidNext: uidNext)
            let found = try search(range, channel: channel, secret: secret)
            // `lower:*` also matches the highest UID when that is below `lower`, so results are filtered.
            let smallest = found.smallest(limit + 1, above: lower - 1)
            if !smallest.isEmpty || range.isFinal {
                let candidates = fittingOneCommand(Array(smallest.prefix(limit)))
                let hasMore = candidates.count < smallest.count || !range.isFinal
                return IMAPNewMessages(candidates: candidates, hasMore: hasMore, emptyThrough: emptyThrough)
            }
            guard let upper = range.upper, upper < UInt32.max else { break }
            emptyThrough = upper
            lower = upper + 1
        }
        return IMAPNewMessages(candidates: [], hasMore: true, emptyThrough: emptyThrough)
    }

    /// The longest prefix of ascending `uids` whose set fits `IMAPPassLimits.maxSetTextBytes`.
    static func fittingOneCommand(_ uids: [UInt32]) -> [UInt32] {
        func fits(_ count: Int) -> Bool {
            IMAPUIDSet(Array(uids.prefix(count))).commandText.utf8.count <= IMAPPassLimits.maxSetTextBytes
        }
        if fits(uids.count) { return uids }
        var low = 1
        var high = uids.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) { low = middle } else { high = middle - 1 }
        }
        return Array(uids.prefix(low))
    }

    private static func search(_ range: IMAPSearchRange, channel: IMAPCommandChannel, secret: Sensitive<String>)
        throws(IMAPPassFailure) -> IMAPUIDSet
    {
        var found = IMAPUIDSet()
        let command = IMAPCommand.uidSearch(range)
        let completion = try channel.run(command, framing: IMAPPassLimits.smallResponses, wait: .completeResponse) {
            (response: IMAPResponse) throws(IMAPPassFailure) in
            switch response {
            case .search(let set):
                found = found.union(set)
            case .extendedSearch(let result):
                // An ESEARCH correlated with another tag is not this command's result.
                if let tag = result.tag, tag != channel.currentTag { return }
                guard result.isUID else {
                    throw .failed(.parse, "the IMAP server answered UID SEARCH with message numbers instead of UIDs")
                }
                found = found.union(result.all)
            default:
                break
            }
        }
        guard completion.status == .ok else {
            throw IMAPFailureClassification.refused(command, completion, secret: secret)
        }
        return found
    }
}
