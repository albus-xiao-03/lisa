// One task in detail (UI-02, UI-03): its fields, completing, reopening or setting its status, editing it, and
// resolving a change the host refused because the task changed there.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// A task as the host has it, with its actions. A refused change is shown next to the task's current state; the owner
/// applies it again to the current version or discards it, and nothing overwrites the newer state silently.
/// Command-Return completes the task.
struct TaskDetailView: View {
    let model: TasksModel
    let taskID: String
    @State private var isEditing = false

    var body: some View {
        Group {
            if let task = model.task(id: taskID) {
                details(of: task)
                    .sheet(isPresented: $isEditing) {
                        TaskEditView(model: model, task: task)
                    }
            } else {
                ContentUnavailableView(
                    "Task Not Shown", systemImage: "checklist",
                    description: Text("This task isn't in the list now. Refresh the tasks to see it again."))
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(of task: TaskDTO) -> some View {
        Form {
            Section {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                    .font(.headline)
                LabeledContent("Status", value: TaskText.status(task.status))
                LabeledContent("Priority", value: TaskText.priority(task.priority))
                if let deadline = task.deadline {
                    LabeledContent("Deadline", value: TaskText.deadline(deadline))
                } else if let phrase = task.unresolvedDeadlineText {
                    LabeledContent("Deadline", value: "“\(phrase)”, not a date yet")
                }
                if let minutes = task.estimatedMinutes {
                    LabeledContent("Estimate", value: "\(minutes) minutes")
                }
                if task.confirmation != .confirmed {
                    LabeledContent("Kind", value: task.confirmation == .possible ? "Possible task" : "For information")
                }
            }
            if !task.notes.isEmpty {
                Section("Notes") {
                    Text(task.notes)
                        .textSelection(.enabled)
                }
            }
            if let conflict = model.conflicts[taskID] {
                conflictSection(conflict)
            } else if model.pendingChanges[taskID] != nil {
                Section {
                    SyncBadge(kind: .waiting)
                }
            }
            Section {
                actions(for: task)
            }
            if let outcome = model.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
                    .disabled(model.busyTaskIDs.contains(taskID))
            }
        }
    }

    @ViewBuilder
    private func actions(for task: TaskDTO) -> some View {
        let isBusy = model.busyTaskIDs.contains(task.id)
        if task.status == .completed {
            Button("Reopen", systemImage: "arrow.uturn.backward") {
                Task { await model.reopen(task) }
            }
            .disabled(isBusy)
        } else {
            Button("Mark Complete", systemImage: "checkmark.circle") {
                Task { await model.complete(task) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isBusy)
        }
        Menu(
            content: {
                ForEach(TaskStatusValue.allCases, id: \.self) { status in
                    Button(TaskText.status(status)) {
                        Task { await model.setStatus(status, of: task) }
                    }
                    .disabled(status == task.status)
                }
            },
            label: { Label("Set Status", systemImage: "circle.dashed") }
        )
        .disabled(isBusy)
        if isBusy {
            ProgressView()
        }
    }

    private func conflictSection(_ conflict: TaskConflict) -> some View {
        Section(
            content: {
                if let change = conflict.change {
                    ForEach(Self.lines(describing: change), id: \.self) { line in
                        Text(line)
                    }
                }
                if let current = conflict.current {
                    LabeledContent("Now on your host", value: TaskText.status(current.status))
                }
                ConflictNotice(
                    message: conflict.conflict.message, canApplyAgain: conflict.conflict.entryID != nil,
                    applyAgain: { await model.applyAgain(taskID: conflict.taskID) },
                    discard: { await model.discardChange(taskID: conflict.taskID) })
                Button("Reload This Task", systemImage: "arrow.clockwise") {
                    Task { await model.reloadTask(id: conflict.taskID) }
                }
            },
            header: { Text("Your Change Wasn't Applied") })
    }

    /// The refused change, one line per field it sets.
    private static func lines(describing change: TaskPatchRequest) -> [String] {
        var lines: [String] = []
        if let status = change.status { lines.append("Status: \(TaskText.status(status))") }
        if let title = change.title { lines.append("Title: \(title)") }
        if change.notes != nil { lines.append("Notes changed") }
        if let priority = change.priority { lines.append("Priority: \(TaskText.priority(priority))") }
        if let deadline = change.deadline { lines.append("Deadline: \(TaskText.deadline(deadline))") }
        if change.clearDeadline == true { lines.append("Deadline removed") }
        if let minutes = change.estimatedMinutes { lines.append("Estimate: \(minutes) minutes") }
        return lines
    }
}
