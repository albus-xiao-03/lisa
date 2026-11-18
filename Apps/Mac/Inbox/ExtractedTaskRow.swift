// One task Lisa extracted as a possible commitment: what it is, when it is due and what it is based on, and confirming
// it as the owner's, correcting it, or dismissing it, which cancels it.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// An extracted task with its review actions (UI-01: extracted items needing review).
struct ExtractedTaskRow: View {
    let model: InboxModel
    let task: TaskDTO
    /// Opens the correction sheet.
    let correct: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                    .font(.headline)
                if let details {
                    Text(details)
                        .font(.callout)
                }
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.taskConflicts[task.id] != nil {
                    SyncBadge(kind: .conflict)
                } else if model.pendingTaskChanges[task.id] != nil {
                    SyncBadge(kind: .waiting)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button("It's Mine") {
                    Task { await model.confirm(task) }
                }
                .help("Confirms the task as your commitment.")
                Button("Correct…", action: correct)
                Button(
                    role: .destructive, action: { Task { await model.dismiss(task) } },
                    label: { Text("Not Mine") }
                )
                .help("Dismisses the task, which cancels it.")
                if model.busyItemIDs.contains(task.id) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .controlSize(.small)
            .disabled(model.busyItemIDs.contains(task.id))
            if let refused = model.taskConflicts[task.id] {
                ConflictNotice(
                    message: refused.conflict.message, canApplyAgain: refused.conflict.canApplyToCurrentRevision,
                    applyAgain: { await model.applyAgain(taskID: task.id) },
                    discard: { await model.discardChange(taskID: task.id) })
            }
        }
        .padding(.vertical, 4)
    }

    /// The deadline, a high or urgent priority and the estimate.
    private var details: String? {
        var parts: [String] = []
        if let deadline = task.deadline {
            parts.append("Due \(TaskText.deadline(deadline))")
        } else if let phrase = task.unresolvedDeadlineText {
            parts.append("Due “\(phrase)”")
        }
        if task.priority == .high || task.priority == .urgent { parts.append(TaskText.priority(task.priority)) }
        if let minutes = task.estimatedMinutes { parts.append("\(minutes) min") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var evidence: String {
        switch task.evidenceCount {
        case 0: "Lisa found this without quoting a source."
        case 1: "Based on 1 piece of evidence."
        default: "Based on \(task.evidenceCount) pieces of evidence."
        }
    }
}
