// The correction sheet of an extracted task: its title, notes, priority, estimate and deadline, sent as one change
// against the version the owner saw, confirming the task as the owner's unless the owner says not to.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Corrects an extracted task (UI-01). Only the fields the owner changed are sent; the deadline stays as it is unless
/// the owner removes it or sets a new one.
struct TaskCorrectionSheet: View {
    let model: InboxModel
    let task: TaskDTO

    /// What happens to the task's deadline.
    private enum DeadlineChoice: Hashable {
        case keep
        case remove
        case set
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var priority: TaskPriorityValue
    @State private var estimate: String
    @State private var deadlineChoice = DeadlineChoice.keep
    @State private var deadline: Date
    @State private var confirming = true
    @State private var problem: String?
    @State private var outcome: ActionOutcome?
    @State private var isSaving = false

    /// A sheet that corrects `task` through `model`, starting from the task as shown.
    init(model: InboxModel, task: TaskDTO) {
        self.model = model
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _priority = State(initialValue: task.priority)
        _estimate = State(initialValue: task.estimatedMinutes.map(String.init) ?? "")
        _deadline = State(initialValue: task.deadline?.instant ?? Date())
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriorityValue.allCases, id: \.self) { value in
                        Text(TaskText.priority(value)).tag(value)
                    }
                }
                TextField("Estimate (minutes)", text: $estimate)
            }
            Section("Deadline") {
                Picker("Deadline", selection: $deadlineChoice) {
                    Text(keepTitle).tag(DeadlineChoice.keep)
                    Text("Remove it").tag(DeadlineChoice.remove)
                    Text("Set a new one").tag(DeadlineChoice.set)
                }
                if deadlineChoice == .set {
                    DatePicker("Due", selection: $deadline)
                }
            }
            Section {
                Toggle("Confirm it as my commitment", isOn: $confirming)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            if let outcome {
                ActionOutcomeLabel(outcome: outcome)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
    }

    /// The choice that keeps the deadline, naming it.
    private var keepTitle: String {
        task.deadline.map { "Keep: \(TaskText.deadline($0))" } ?? "Keep: none"
    }

    private func save() async {
        let trimmedEstimate = estimate.trimmingCharacters(in: .whitespaces)
        var minutes: Int?
        if !trimmedEstimate.isEmpty {
            guard let parsed = Int(trimmedEstimate) else {
                problem = "Enter the estimate as a number of minutes."
                return
            }
            minutes = parsed
        }
        var edit = TaskEdit()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != task.title { edit.title = trimmedTitle }
        if notes != task.notes { edit.notes = notes }
        if priority != task.priority { edit.priority = priority }
        if let minutes, minutes != task.estimatedMinutes { edit.estimatedMinutes = minutes }
        switch deadlineChoice {
        case .keep: break
        case .remove: edit.clearDeadline = task.deadline != nil
        case .set: edit.deadline = DeadlineDTO(instant: deadline, zone: TimeZone.current.identifier)
        }
        if !edit.isEmpty, let issue = edit.problem {
            problem = issue
            return
        }
        problem = nil
        isSaving = true
        defer { isSaving = false }
        let result = await model.correct(task, edit, confirming: confirming)
        outcome = result
        if result.isDone || result.isQueued { dismiss() }
    }
}
