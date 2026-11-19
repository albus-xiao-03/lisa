// A refused action whose subject changed on the host (409): shown as recoverable, never overwritten silently (UI-03).

import Foundation
import LisaClient

/// An action the host refused because its subject changed since the owner saw it (UI-03). It is recoverable: the owner
/// reviews the current state, then applies the action again to the current revision or discards it.
public struct ActionConflict: Hashable, Sendable {
    /// The queued entry that holds the refused action, to apply again or discard; `nil` when it was not queued.
    public var entryID: String?
    /// The subject's current revision on the host, when the host said.
    public var currentRevision: Int64?
    /// The host's explanation, without private content.
    public var message: String

    /// A conflict on the queued entry `entryID`.
    public init(entryID: String?, currentRevision: Int64?, message: String) {
        self.entryID = entryID
        self.currentRevision = currentRevision
        self.message = message
    }

    /// The conflict a queued entry holds, or `nil` when the entry is not a conflict.
    public init?(entry: QueuedRequest) {
        guard entry.status == .conflict, case .conflict(let conflict) = ActionOutcome(entry) else { return nil }
        self = conflict
    }

    /// Whether the action can be applied again to the current revision. Without one, the subject can no longer take
    /// the action (for example, a reminder that was already acknowledged), and the action can only be discarded.
    public var canApplyToCurrentRevision: Bool { entryID != nil && currentRevision != nil }
}
