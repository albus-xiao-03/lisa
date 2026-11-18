// One block of the rundown: its times, title and kind, whether it is a suggestion, locked, done or set aside, and the
// owner's actions on it, with a mark while an action waits to sync or was refused because the plan changed.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// A planned block as Today shows it, in the rundown's own time zone, with the actions it offers
/// (`PlanBlockActions.available(for:)`): the main one as a button and the rest in a menu. Calendar events offer none.
/// While an action on the block waits to sync or was refused, or any block action is being sent, the actions are
/// disabled; a refused action is resolved in Today's list of actions not applied.
struct PlanBlockRow: View {
    let block: PlanBlockDTO
    let zone: TimeZone
    let model: RundownModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(times)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, alignment: .leading)
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
                    if model.blockConflicts[block.blockID] != nil {
                        SyncBadge(kind: .conflict)
                    } else if model.pendingBlockActions[block.blockID] != nil {
                        SyncBadge(kind: .waiting)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if model.busyBlockIDs.contains(block.blockID) {
                ProgressView()
                    .controlSize(.small)
            }
            actionControls
                .disabled(!canAct)
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        if let main = actions.first {
            Button(PlanBlockActions.label(for: main)) { act(main) }
                .controlSize(.small)
                .accessibilityLabel("\(PlanBlockActions.label(for: main)) \(title)")
            if actions.count > 1 {
                Menu(
                    content: {
                        ForEach(actions.dropFirst(), id: \.self) { action in
                            Button(PlanBlockActions.label(for: action)) { act(action) }
                        }
                    },
                    label: { Label("Actions", systemImage: "ellipsis.circle") }
                )
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(title)")
            }
        }
    }

    private var title: String { block.title.isEmpty ? "Untitled block" : block.title }

    private var actions: [PlanBlockActionKind] { PlanBlockActions.available(for: block) }

    /// Whether the owner can act now: nothing is being sent, and no action on this block waits or was refused.
    private var canAct: Bool {
        model.busyBlockIDs.isEmpty && model.pendingBlockActions[block.blockID] == nil
            && model.blockConflicts[block.blockID] == nil
    }

    private func act(_ action: PlanBlockActionKind) {
        Task { await model.act(action, on: block) }
    }

    private var times: String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        return "\(block.start.formatted(style)) – \(block.end.formatted(style))"
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
