// One open task on Today: complete or reopen it against the version shown, with its deadline and priority, and a mark
// when its change waits to sync or was refused because the task changed on the host.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// A task with its completion control (UI-01: tasks and quick actions). Completing queues the change durably and sends
/// it at once when possible; the row then shows it waiting, or the host's refusal as a recoverable conflict.
struct TodayTaskRow: View {
    let task: TaskDTO
    let model: TasksModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(isBusy)
                .accessibilityLabel(isDone ? "Reopen \(title)" : "Complete \(title)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let details {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.conflicts[task.id] != nil {
                        SyncBadge(kind: .conflict)
                    } else if model.pendingChanges[task.id] != nil {
                        SyncBadge(kind: .waiting)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if let conflict = model.conflicts[task.id] {
                ConflictNotice(
                    message: conflict.conflict.message, canApplyAgain: conflict.conflict.canApplyToCurrentRevision,
                    applyAgain: { await model.applyAgain(taskID: task.id) },
                    discard: { await model.discardChange(taskID: task.id) })
            }
        }
    }

    private var title: String { task.title.isEmpty ? "Untitled task" : task.title }

    private var isDone: Bool { task.status == .completed }

    private var isBusy: Bool { model.busyTaskIDs.contains(task.id) }

    /// The status when not open, a high or urgent priority, the deadline and the estimate.
    private var details: String? {
        var parts: [String] = []
        if task.status != .open { parts.append(TaskText.status(task.status)) }
        if task.priority == .high || task.priority == .urgent { parts.append(TaskText.priority(task.priority)) }
        if let deadline = task.deadline {
            parts.append("Due \(TaskText.deadline(deadline))")
        } else if let phrase = task.unresolvedDeadlineText {
            parts.append("Due “\(phrase)”")
        }
        if let minutes = task.estimatedMinutes { parts.append("\(minutes) min") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func toggle() {
        Task {
            if isDone {
                await model.reopen(task)
            } else {
                await model.complete(task)
            }
        }
    }
}
