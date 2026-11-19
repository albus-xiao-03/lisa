// A plan-block action the host refused because the plan changed meanwhile, with the action and the block as the
// current plan has it.

import Foundation
import LisaAPIContract

/// An action on a plan block that the host refused because the plan changed since the owner saw it (UI-03), for
/// example because the planner or another action changed it first. The screen shows the block as the plan shown has it
/// next to the refused action; the owner applies the action again to that plan or discards it.
public struct PlanBlockConflict: Hashable, Sendable {
    /// The plan's identifier.
    public var planID: String
    /// The block's identifier.
    public var blockID: String
    /// The action that was refused.
    public var action: PlanBlockActionKind
    /// The refusal, with its queued entry and the plan's current revision.
    public var conflict: ActionConflict
    /// The block as the plan shown has it, or `nil` when it is no longer in that plan.
    public var current: PlanBlockDTO?

    /// A conflict on `blockID` of `planID`.
    public init(
        planID: String, blockID: String, action: PlanBlockActionKind, conflict: ActionConflict, current: PlanBlockDTO?
    ) {
        self.planID = planID
        self.blockID = blockID
        self.action = action
        self.conflict = conflict
        self.current = current
    }

    /// Whether the action can be applied again: it is still queued, the block is still in the plan, and the block still
    /// offers the action in its current state (`PlanBlockActions.offers(_:on:)`, which includes moving). Otherwise it can
    /// only be discarded.
    public var canApplyAgain: Bool {
        guard conflict.entryID != nil, let current else { return false }
        return PlanBlockActions.offers(action, on: current)
    }
}
