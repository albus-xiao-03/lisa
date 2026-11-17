// A proposal review the host refused because the proposal changed meanwhile, with the action and the current proposal.

import Foundation
import LisaAPIContract

/// A review action on an event proposal that the host refused because the proposal changed since the owner saw it
/// (UI-03). The inbox shows the current proposal next to the refused action; the owner applies the action again to the
/// current version or discards it.
public struct ProposalConflict: Hashable, Sendable {
    /// The proposal's identifier.
    public var proposalID: String
    /// The refused action, with its queued entry and the proposal's current revision.
    public var conflict: ActionConflict
    /// The action that was refused.
    public var action: ProposalActionRequest?
    /// The proposal as the host has it now, once it could be read.
    public var current: EventProposalDTO?

    /// A conflict on `proposalID`.
    public init(
        proposalID: String, conflict: ActionConflict, action: ProposalActionRequest?, current: EventProposalDTO?
    ) {
        self.proposalID = proposalID
        self.conflict = conflict
        self.action = action
        self.current = current
    }
}
