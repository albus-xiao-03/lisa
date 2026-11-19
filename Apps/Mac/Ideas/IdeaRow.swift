// One idea in the list: its summary, stage, priority, estimate, deadline and tags, why the planner couldn't place it,
// and its actions: edit, set the priority, offer for planning, move to another stage or archive.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// An idea with its actions (UI-01: edit, prioritize, schedule and archive). The stages offered are those the host
/// allows from the idea's stage (`IdeasModel.stages(after:)`); the host stays the authority.
struct IdeaRow: View {
    let model: IdeasModel
    let idea: IdeaDTO
    /// Opens the edit sheet.
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.summary.isEmpty ? idea.originalCapture : idea.summary)
                        .lineLimit(3)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = IdeasModel.schedulingNote(for: idea) {
                        Label(note, systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if model.conflicts[idea.id] != nil {
                        SyncBadge(kind: .conflict)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if model.busyIdeaIDs.contains(idea.id) {
                    ProgressView()
                        .controlSize(.small)
                }
                if stages.contains(.availableForPlanning) {
                    Button("Plan") {
                        Task { await model.offerForPlanning(idea) }
                    }
                    .controlSize(.small)
                    .help("Offers the idea for planning; Lisa's planner then suggests a block for it.")
                }
                Menu(
                    content: { actions },
                    label: { Label("Actions", systemImage: "ellipsis.circle") }
                )
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Actions for this idea")
            }
            .disabled(model.busyIdeaIDs.contains(idea.id))
            if let refused = model.conflicts[idea.id] {
                ConflictNotice(
                    message: refused.conflict.message, canApplyAgain: refused.canApplyAgain,
                    applyAgain: { await model.applyAgain(ideaID: idea.id) },
                    discard: { model.discardChange(ideaID: idea.id) })
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var actions: some View {
        Button("Edit…", action: edit)
        Menu("Priority") {
            ForEach(TaskPriorityValue.allCases, id: \.self) { priority in
                Button(TaskText.priority(priority)) {
                    Task { await model.setPriority(priority, of: idea) }
                }
                .disabled(priority == idea.priority)
            }
        }
        Divider()
        ForEach(stages, id: \.self) { stage in
            Button(Self.moveTitle(stage, from: idea.lifecycle)) {
                Task { await model.move(idea, to: stage) }
            }
        }
    }

    private var stages: [IdeaLifecycleValue] { IdeasModel.stages(after: idea.lifecycle) }

    /// The stage, the priority when not normal, the estimate, the deadline and the tags.
    private var details: String {
        var parts = [IdeasModel.label(for: idea.lifecycle)]
        if idea.priority != .normal { parts.append("\(TaskText.priority(idea.priority)) priority") }
        if let minutes = idea.estimatedMinutes { parts.append("\(minutes) min") }
        if let deadline = idea.deadline { parts.append("By \(TaskText.deadline(deadline))") }
        if !idea.tags.isEmpty { parts.append(idea.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// The menu title of moving an idea from `current` to `stage`.
    private static func moveTitle(_ stage: IdeaLifecycleValue, from current: IdeaLifecycleValue) -> String {
        switch stage {
        case .inbox: current == .archived ? "Restore to Inbox" : "Move to Inbox"
        case .availableForPlanning: "Offer for Planning"
        case .scheduled: "Mark as Scheduled"
        case .explored: "Mark as Explored"
        case .archived: "Archive"
        }
    }
}
