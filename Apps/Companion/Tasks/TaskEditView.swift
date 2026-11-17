// The task-edit sheet: title, notes, priority, estimate and removing the deadline, saved through the durable queue
// against the version the owner saw.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Edits one task. Saving closes the sheet once the change is done or saved for later; otherwise the sheet stays open
/// with the outcome, so nothing the owner wrote is lost.
struct TaskEditView: View {
    let model: TasksModel
    let task: TaskDTO
    @State private var form: TaskEditForm
    @State private var outcome: ActionOutcome?
    @Environment(\.dismiss) private var dismiss

    init(model: TasksModel, task: TaskDTO) {
        self.model = model
        self.task = task
        _form = State(initialValue: TaskEditForm(task: task))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $form.title)
                }
                Section("Notes") {
                    TextField("Notes", text: $form.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    Picker("Priority", selection: $form.priority) {
                        ForEach(TaskPriorityValue.allCases, id: \.self) { priority in
                            Text(TaskText.priority(priority)).tag(priority)
                        }
                    }
                    if task.estimatedMinutes == nil {
                        Toggle("Estimate", isOn: $form.hasEstimate)
                    }
                    if form.hasEstimate {
                        Stepper(
                            "\(form.estimatedMinutes) minutes", value: $form.estimatedMinutes, in: 1...1_440, step: 5)
                    }
                    if task.deadline != nil {
                        Toggle("Remove the Deadline", isOn: $form.removesDeadline)
                    }
                }
                if let outcome {
                    Section {
                        ActionOutcomeLabel(outcome: outcome)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.busyTaskIDs.contains(task.id))
                }
            }
        }
    }

    private func save() {
        let edit = form.edit(of: task)
        Task {
            let result = await model.edit(task, edit)
            outcome = result
            if result.isDone || result.isQueued { dismiss() }
        }
    }
}
