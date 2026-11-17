// One task in the list: its title, status, priority, deadline and estimate, and whether a change waits to sync or was
// refused because the task changed on the host.

import LisaAPIContract
import SwiftUI

/// A task as the tasks list shows it.
struct TaskRow: View {
    let task: TaskDTO
    let hasPendingChange: Bool
    let hasConflict: Bool
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .completed ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                if let details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasConflict {
                    SyncBadge(kind: .conflict)
                } else if hasPendingChange {
                    SyncBadge(kind: .waiting)
                }
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Status when not open, a high or urgent priority, the deadline and the estimate.
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
}
