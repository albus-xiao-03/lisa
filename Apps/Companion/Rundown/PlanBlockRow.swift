// One block of the rundown: its times, title and kind, whether it is a suggestion, locked, done or set aside, and the
// owner's actions on it, moving it included, with a mark while an action waits to sync or was refused because the plan
// changed.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// A planned block as the rundown shows it, in the rundown's own zone, with the actions it offers
/// (`PlanBlockActions.available(for:)`): the main one as a button and the rest in a menu, with "Move…" there when the
/// block can be moved (`PlanBlockActions.canMove(_:)`), which opens `PlanBlockMoveForm`. Calendar events offer none.
/// While an action on the block waits to sync or was refused, or any block action is being sent, the actions are
/// disabled; a waiting or refused move shows the times it asks for, and a refused action is resolved at the top of the
/// rundown. At accessibility text sizes the times move above the title.
struct PlanBlockRow: View {
    let block: PlanBlockDTO
    let zone: TimeZone
    let model: RundownModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isMoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            details
                .accessibilityElement(children: .combine)
            if model.blockConflicts[block.blockID] != nil {
                SyncBadge(kind: .conflict)
            } else if let pending = model.pendingBlockActions[block.blockID] {
                SyncBadge(kind: .waiting, action: PlanBlockActions.label(for: pending))
            }
            if let requested = model.requestedMoves[block.blockID] {
                Text("Move to \(format(requested))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !actions.isEmpty || canMove {
                HStack(spacing: 8) {
                    if let main = actions.first {
                        Button(PlanBlockActions.label(for: main)) { act(main) }
                            .accessibilityLabel("\(PlanBlockActions.label(for: main)) \(title)")
                    }
                    if !menuActions.isEmpty || canMove {
                        Menu(
                            content: {
                                ForEach(menuActions, id: \.self) { action in
                                    Button(PlanBlockActions.label(for: action)) { act(action) }
                                }
                                if canMove {
                                    Button("Move…", systemImage: "clock.arrow.2.circlepath") { isMoving = true }
                                }
                            },
                            label: { Label("More", systemImage: "ellipsis") }
                        )
                        .menuStyle(.button)
                        .accessibilityLabel("More actions for \(title)")
                    }
                    if model.busyBlockIDs.contains(block.blockID) {
                        ProgressView()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canAct)
            }
        }
        .sheet(isPresented: $isMoving) {
            PlanBlockMoveForm(block: block, zone: zone, model: model)
        }
    }

    private var details: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(times)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !block.explanation.isEmpty {
                    Text(block.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var title: String { block.title.isEmpty ? "Untitled block" : block.title }

    private var actions: [PlanBlockActionKind] { PlanBlockActions.available(for: block) }

    /// The actions after the main one, for the menu.
    private var menuActions: [PlanBlockActionKind] { Array(actions.dropFirst()) }

    private var canMove: Bool { PlanBlockActions.canMove(block) }

    /// Whether the owner can act now: nothing is being sent, and no action on this block waits or was refused.
    private var canAct: Bool {
        model.busyBlockIDs.isEmpty && model.pendingBlockActions[block.blockID] == nil
            && model.blockConflicts[block.blockID] == nil
    }

    private func act(_ action: PlanBlockActionKind) {
        Task { await model.act(action, on: block) }
    }

    private var times: String {
        format(PlanBlockTimes(of: block))
    }

    private func format(_ times: PlanBlockTimes) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        return "\(times.start.formatted(style)) – \(times.end.formatted(style))"
    }

    private var symbol: String {
        switch block.kind {
        case "fixedEvent": "calendar"
        case "task": "checkmark.circle"
        case "idea": "lightbulb"
        default: "circle"
        }
    }

    /// The block's state when it is not simply accepted, and whether its times may change.
    private var status: String? {
        var parts: [String] = []
        switch block.state {
        case "proposed": parts.append("Suggested")
        case "locked": parts.append("Locked")
        case "completed": parts.append("Done")
        case "rejected": parts.append("Declined")
        case "deferred": parts.append("Deferred")
        default: break
        }
        if block.provisional { parts.append("Times may change") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
