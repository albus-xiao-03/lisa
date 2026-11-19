// Plans one pass from the sizes the server reported (OPS-02): which messages to download within the per-pass item
// and byte limits, and which are too large to download, so they are reported instead of silently dropped.

/// The ordered decisions for the candidate UIDs of one pass.
struct IMAPPassPlan: Hashable, Sendable {
    enum Step: Hashable, Sendable {
        /// Download this message.
        case fetch(uid: UInt32, size: UInt64)
        /// Larger than the message limit: not downloaded but reported in a note, and the cursor moves past it.
        case skipOversized(uid: UInt32, size: UInt64)
    }

    var steps: [Step]
    /// Whether messages remain after the last step.
    var hasMore: Bool

    var fetchUIDs: [UInt32] {
        steps.compactMap { step in
            if case .fetch(let uid, _) = step { uid } else { nil }
        }
    }

    /// The sum of the reported sizes of the messages to download.
    var plannedBytes: Int {
        steps.reduce(0) { total, step in
            if case .fetch(_, let size) = step { total + Int(size) } else { total }
        }
    }

    /// Takes `candidates` in ascending UID order until the item or byte limit is reached. A candidate without a
    /// reported size ends the plan, so it is read again later; if it is the first one, the pass fails as partial.
    static func make(
        candidates: [UInt32], sizes: [UInt32: UInt64], limits: IMAPPassLimits, moreAfterCandidates: Bool
    ) throws(IMAPPassFailure) -> IMAPPassPlan {
        var plan = IMAPPassPlan(steps: [], hasMore: moreAfterCandidates)
        var fetchCount = 0
        var planned: UInt64 = 0
        let messageLimit = UInt64(limits.messageLimit)
        for uid in candidates {
            guard let size = sizes[uid] else {
                if plan.steps.isEmpty {
                    throw .failed(
                        .partial,
                        "the IMAP server listed message UID \(uid) but did not report its size; it is read again on "
                            + "the next attempt")
                }
                plan.hasMore = true
                break
            }
            if size > messageLimit {
                plan.steps.append(.skipOversized(uid: uid, size: size))
                continue
            }
            if fetchCount == limits.maxItems || planned + size > UInt64(limits.maxBytes) {
                plan.hasMore = true
                break
            }
            plan.steps.append(.fetch(uid: uid, size: size))
            fetchCount += 1
            planned += size
        }
        return plan
    }
}
