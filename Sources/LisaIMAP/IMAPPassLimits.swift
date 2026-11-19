// The bounds of one fetch pass (OPS-02): response sizes for each kind of command, the length of a UID set in a
// command, and the effective size limit for one message.

/// Fixed protocol bounds and the per-pass limits derived from SyncLimits and the settings.
struct IMAPPassLimits: Hashable, Sendable {
    /// The longest response text accepted, literal data excluded. A bounded search window's result stays far below.
    static let maxLineBytes = 1_048_576
    /// The largest literal accepted outside message bodies, such as a mailbox name in a LIST response.
    static let maxSmallLiteralBytes = 65_536
    /// The most literals in one response.
    static let maxLiteralsPerResponse = 16
    /// The longest UID set Lisa writes into one command. RFC 7162 §4 recommends that clients keep command lines to
    /// about 8192 octets, because servers may answer longer ones with BAD; a pass takes fewer UIDs when a sparse set
    /// would be longer.
    static let maxSetTextBytes = 4_000
    /// The most messages one pass takes, whatever SyncLimits asks for (configuration allows at most 5000).
    static let maxItemsCeiling = 100_000

    let maxItems: Int
    let maxBytes: Int
    /// The largest message downloaded: the configured message limit, or the pass byte limit if that is smaller,
    /// because a message is never split across passes.
    let messageLimit: Int

    init(maxItems: Int, maxBytes: Int, maxMessageBytes: Int) {
        self.maxItems = min(max(1, maxItems), Self.maxItemsCeiling)
        self.maxBytes = max(1, maxBytes)
        messageLimit = max(1, min(maxMessageBytes, self.maxBytes))
    }

    /// Limits for EXAMINE, UID SEARCH and the size probe, whose responses carry no message content.
    static var smallResponses: IMAPFramingLimits {
        IMAPFramingLimits(
            maxLineBytes: maxLineBytes, maxLiteralBytes: maxSmallLiteralBytes,
            maxLiteralsPerResponse: maxLiteralsPerResponse, literalBudget: maxLineBytes)
    }

    /// Limits for fetching messages planned at `plannedBytes`: each literal at most the message limit, and all of
    /// them at most one message limit beyond the plan, which tolerates servers whose RFC822.SIZE is slightly off.
    func messageResponses(plannedBytes: Int) -> IMAPFramingLimits {
        IMAPFramingLimits(
            maxLineBytes: Self.maxLineBytes, maxLiteralBytes: messageLimit,
            maxLiteralsPerResponse: Self.maxLiteralsPerResponse, literalBudget: plannedBytes + messageLimit)
    }
}
