// One fetch pass over an authenticated session (plan §7.3): EXAMINE the folder, find UIDs above the cursor, probe
// their sizes, download the planned messages with BODY.PEEK[], and build the batch with the next cursor (MAIL-02).

import Foundation
import LisaPorts
import LisaRedaction
import LisaTime

/// The cursor a pass starts from.
enum IMAPStartingPoint: Hashable, Sendable {
    /// No cursor: the folder is read from its first message.
    case beginning
    /// A cursor that could not be read: the folder is read from its first message, and the batch says so.
    case unreadableCursor
    case cursor(IMAPSyncCursor)
}

/// Runs the commands of one pass and assembles its batch. The cursor in the batch never passes a message that was
/// neither delivered nor reported.
struct IMAPFetchPass {
    let channel: IMAPCommandChannel
    let folder: IMAPMailboxName
    let start: IMAPStartingPoint
    let limits: IMAPPassLimits
    let clock: any WallClock
    let secret: Sensitive<String>

    func run() throws(IMAPPassFailure) -> FetchBatch {
        var notes: [String] = []
        let state = try IMAPFolderExamination.examine(folder, on: channel, secret: secret)
        var last: UInt32 = 0
        switch start {
        case .beginning:
            break
        case .unreadableCursor:
            notes.append(
                "the stored mailbox position could not be read, so the folder is read again from its first message; "
                    + "messages already stored are recognized and not stored twice")
        case .cursor(let cursor):
            guard cursor.folder == folder.name else {
                throw .failed(
                    .configuration,
                    "this source was synchronized from a different folder; configure a new source key to read "
                        + "another folder")
            }
            if cursor.uidValidity == state.uidValidity {
                last = cursor.lastUID
            } else {
                notes.append(
                    "the folder's UIDVALIDITY changed from \(cursor.uidValidity) to \(state.uidValidity), so every "
                        + "message is read again; messages already stored are recognized by their Message-ID")
            }
        }
        func batch(_ items: [FetchedItem], through uid: UInt32, hasMore: Bool) -> FetchBatch {
            FetchBatch(
                items: items,
                nextCursor: IMAPSyncCursor(uidValidity: state.uidValidity, lastUID: uid, folder: folder.name).encoded,
                isCompleteSnapshot: false, hasMore: hasMore, capabilityNotes: notes)
        }
        if state.exists == 0 || last == UInt32.max { return batch([], through: last, hasMore: false) }

        let found = try IMAPNewMessageSearch.find(
            above: last, uidNext: state.uidNext, limit: limits.maxItems, channel: channel, secret: secret)
        let floor = max(last, found.emptyThrough ?? 0)
        guard !found.candidates.isEmpty else { return batch([], through: floor, hasMore: found.hasMore) }

        let sizes = try probeSizes(of: found.candidates)
        let plan = try IMAPPassPlan.make(
            candidates: found.candidates, sizes: sizes, limits: limits, moreAfterCandidates: found.hasMore)
        let bodies = try download(plan)
        let assembled = try IMAPPassAssembly.assemble(plan, bodies: bodies, after: floor, limits: limits)
        notes += assembled.notes
        let items = assembled.messages.map { message in
            FetchedItem(
                externalID: "imap:\(state.uidValidity):\(message.uid)", kind: .email, data: message.data,
                receivedAt: clock.now(),
                metadata: ["uid": String(message.uid), "uidValidity": String(state.uidValidity)])
        }
        return batch(items, through: assembled.lastUID, hasMore: assembled.hasMore)
    }

    /// `UID FETCH <set> (UID RFC822.SIZE)`: the sizes of the candidates, so the pass is planned before any message
    /// is transferred.
    private func probeSizes(of uids: [UInt32]) throws(IMAPPassFailure) -> [UInt32: UInt64] {
        let set = IMAPUIDSet(uids)
        var sizes: [UInt32: UInt64] = [:]
        let command = IMAPCommand.uidFetchSizes(set)
        let completion = try channel.run(command, framing: IMAPPassLimits.smallResponses, wait: .completeResponse) {
            (response: IMAPResponse) throws(IMAPPassFailure) in
            guard case .fetch(_, let data) = response, let uid = data.uid, let size = data.size, set.contains(uid),
                sizes[uid] == nil
            else { return }
            sizes[uid] = size
        }
        guard completion.status == .ok else {
            throw IMAPFailureClassification.refused(command, completion, secret: secret)
        }
        return sizes
    }

    /// `UID FETCH <set> (UID RFC822.SIZE BODY.PEEK[])` for the planned messages. Bodies of UIDs that were not asked
    /// for, and repeated bodies, are discarded; they still count against the command's byte budget.
    private func download(_ plan: IMAPPassPlan) throws(IMAPPassFailure) -> [UInt32: IMAPBodyContent] {
        let uids = plan.fetchUIDs
        guard !uids.isEmpty else { return [:] }
        let set = IMAPUIDSet(uids)
        var bodies: [UInt32: IMAPBodyContent] = [:]
        let command = IMAPCommand.uidFetchMessages(set)
        let framing = limits.messageResponses(plannedBytes: plan.plannedBytes)
        let completion = try channel.run(command, framing: framing, wait: .steadyProgress) {
            (response: IMAPResponse) throws(IMAPPassFailure) in
            guard case .fetch(_, let data) = response, let body = data.body else { return }
            guard let uid = data.uid else {
                throw .failed(.parse, "the IMAP server sent a message without its UID in reply to UID FETCH")
            }
            guard set.contains(uid), bodies[uid] == nil else { return }
            bodies[uid] = body
        }
        guard completion.status == .ok else {
            throw IMAPFailureClassification.refused(command, completion, secret: secret)
        }
        return bodies
    }
}
