// The owner's actions on a block of the rundown (PLAN-04): which ones a block offers in its state, and their names.

import Foundation
import LisaAPIContract

/// The actions the rundown offers on a plan block, and their names for buttons and menus (PLAN-04: the owner accepts,
/// locks, rejects, defers or completes blocks).
///
/// The host applies any of them to a block that is not a calendar event. A calendar event is changed in the calendar,
/// never in the plan, so it offers none. The screens offer what fits the block's state, the main action first:
/// - a suggestion (`proposed`): accept, decline, defer, lock or mark done;
/// - an accepted block: mark done, lock, defer or decline;
/// - a locked block: mark done, defer or decline;
/// - a declined or deferred block: accept, until the planner next replaces it;
/// - a completed block: none.
public enum PlanBlockActions {
    /// The actions `block` offers in its state, the main one first; none for a calendar event.
    public static func available(for block: PlanBlockDTO) -> [PlanBlockActionKind] {
        guard block.kind != "fixedEvent" else { return [] }
        switch block.state {
        case "proposed": return [.accept, .reject, .defer, .lock, .complete]
        case "accepted": return [.complete, .lock, .defer, .reject]
        case "locked": return [.complete, .defer, .reject]
        case "rejected", "deferred": return [.accept]
        default: return []
        }
    }

    /// A name for `action`, such as "Accept" or "Mark Done".
    public static func label(for action: PlanBlockActionKind) -> String {
        switch action {
        case .accept: "Accept"
        case .lock: "Lock"
        case .reject: "Decline"
        case .complete: "Mark Done"
        case .defer: "Defer"
        }
    }

    /// Why `action` cannot be taken on `block`, or `nil` when it can. The reason holds none of the owner's content.
    static func refusal(of action: PlanBlockActionKind, on block: PlanBlockDTO) -> String? {
        if block.kind == "fixedEvent" { return "calendar events are changed in the calendar, not in the plan" }
        guard !available(for: block).contains(action) else { return nil }
        return "this block can't be \(pastParticiple(of: action)) now"
    }

    private static func pastParticiple(of action: PlanBlockActionKind) -> String {
        switch action {
        case .accept: "accepted"
        case .lock: "locked"
        case .reject: "declined"
        case .complete: "marked done"
        case .defer: "deferred"
        }
    }
}
