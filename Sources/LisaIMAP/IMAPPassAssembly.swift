// Turns a pass plan and the message bodies received into the batch content: the messages in UID order within the
// byte limit, the notes for every message not downloaded, and the highest UID the cursor may move to.

import Foundation

/// One downloaded message.
struct IMAPReceivedMessage: Hashable, Sendable {
    var uid: UInt32
    var data: Data
}

/// The content of a successful pass.
struct IMAPAssembledPass: Hashable, Sendable {
    var messages: [IMAPReceivedMessage]
    /// Every message up to this UID was delivered or reported; the next pass continues after it.
    var lastUID: UInt32
    var hasMore: Bool
    var notes: [String]
}

/// Walks the plan in UID order. The cursor stops before the first planned message that did not arrive, so nothing is
/// skipped; messages beyond the byte limit by their actual size wait for the next pass.
enum IMAPPassAssembly {
    static func assemble(
        _ plan: IMAPPassPlan, bodies: [UInt32: IMAPBodyContent], after last: UInt32, limits: IMAPPassLimits
    ) throws(IMAPPassFailure) -> IMAPAssembledPass {
        var result = IMAPAssembledPass(messages: [], lastUID: last, hasMore: plan.hasMore, notes: [])
        var bytes = 0
        for step in plan.steps {
            switch step {
            case .skipOversized(let uid, let size):
                result.notes.append(
                    "message UID \(uid) is \(size) bytes, larger than the \(limits.messageLimit)-byte limit; it was "
                        + "not downloaded and stays in the mailbox")
                result.lastUID = uid
            case .fetch(let uid, _):
                guard let body = bodies[uid] else {
                    if result.lastUID == last {
                        throw .failed(
                            .partial,
                            "the IMAP server did not return message UID \(uid); it is read again on the next attempt")
                    }
                    result.hasMore = true
                    return result
                }
                switch body {
                case .absent:
                    result.notes.append(
                        "the IMAP server has no content for message UID \(uid) (BODY[] NIL); it was skipped")
                    result.lastUID = uid
                case .octets(let data):
                    guard bytes + data.count <= limits.maxBytes else {
                        result.hasMore = true
                        return result
                    }
                    result.messages.append(IMAPReceivedMessage(uid: uid, data: data))
                    bytes += data.count
                    result.lastUID = uid
                }
            }
        }
        return result
    }
}
