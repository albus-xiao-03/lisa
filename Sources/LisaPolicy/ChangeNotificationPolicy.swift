// Coalescing and supersession of important-change notifications (plan §6.4, NOTIFY-03, L32).

import Foundation
import LisaDomain

/// The state of an earlier change occurrence for the same subject.
public struct PriorChangeOccurrence: Hashable, Sendable {
    public var id: NotificationID
    public var changeSequence: Int
    /// Whether any delivery of it reached the submitting phase or a final provider outcome.
    public var anyDeliverySubmitted: Bool

    public init(id: NotificationID, changeSequence: Int, anyDeliverySubmitted: Bool) {
        self.id = id
        self.changeSequence = changeSequence
        self.anyDeliverySubmitted = anyDeliverySubmitted
    }
}

/// What to do when a new material change arrives.
public struct ChangeNotificationPlan: Hashable, Sendable {
    /// Earlier occurrences to cancel as coalesced: those with nothing submitted yet.
    public var coalesce: [NotificationID]
    /// Whether to create the new occurrence.
    public var createNew: Bool
}

/// Rules for change notifications.
public enum ChangeNotificationPolicy {
    /// A new change always produces a new occurrence unless one already exists for this exact change sequence.
    /// Pending, never-submitted earlier occurrences are coalesced into it; delivered ones are left alone.
    public static func plan(newChangeSequence: Int, prior: [PriorChangeOccurrence]) -> ChangeNotificationPlan {
        if prior.contains(where: { $0.changeSequence == newChangeSequence }) {
            return ChangeNotificationPlan(coalesce: [], createNew: false)
        }
        let coalesce = prior.filter { !$0.anyDeliverySubmitted && $0.changeSequence < newChangeSequence }.map(\.id)
        return ChangeNotificationPlan(coalesce: coalesce.sorted(), createNew: true)
    }

    /// At send time: an occurrence that is no longer the latest change is superseded only if nothing was submitted.
    public static func isSuperseded(occurrenceSequence: Int, latestSequence: Int, anySubmitted: Bool) -> Bool {
        occurrenceSequence < latestSequence && !anySubmitted
    }
}
