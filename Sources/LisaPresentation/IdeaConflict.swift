// An idea change the host refused because the idea changed meanwhile, with the change and the current idea.

import Foundation
import LisaAPIContract

/// An idea change the host refused because the idea changed since the owner saw it, or because the idea can no longer
/// move to the chosen stage (UI-03). The screen shows the current idea next to the refused change; the owner applies
/// the change again to the current version or discards it. The change is kept on this device until then, not in the
/// offline queue, so it does not survive an app restart; the host never applied it.
public struct IdeaConflict: Hashable, Sendable {
    /// The idea's identifier.
    public var ideaID: String
    /// The host's refusal, with the idea's current revision when the host said.
    public var conflict: ActionConflict
    /// The change that was refused.
    public var change: IdeaPatchRequest
    /// The idea as the host has it now, once it could be read.
    public var current: IdeaDTO?

    /// A conflict on `ideaID`.
    public init(ideaID: String, conflict: ActionConflict, change: IdeaPatchRequest, current: IdeaDTO?) {
        self.ideaID = ideaID
        self.conflict = conflict
        self.change = change
        self.current = current
    }

    /// Whether the change can be applied again to the idea's current revision. Without one the idea can no longer
    /// take the change, for example a stage it cannot move to, and the change can only be discarded.
    public var canApplyAgain: Bool { conflict.currentRevision != nil }
}
