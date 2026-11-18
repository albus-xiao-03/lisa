// The task-edit sheet: title, notes, priority, estimate, and keeping, removing or setting the deadline, saved through
// the durable queue against the version the owner saw.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Edits one task. A new deadline is a day, or a day and a time, picked on this device's clock, the zone the sheet's
/// date picker shows. Saving closes the sheet once the change is done or saved for later; otherwise the sheet stays
/// open with the outcome, so nothing the owner wrote is lost.
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
                Section(
                    content: {
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
                                "\(form.estimatedMinutes) minutes", value: $form.estimatedMinutes, in: 1...1_440,
                                step: 5)
                        }
                    },
                    footer: {
                        if task.estimatedMinutes != nil {
                            Text("An estimate can be changed but not removed.")
                        }
                    })
                deadlineSection
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

    private var deadlineSection: some View {
        Section("Deadline") {
            Picker("Deadline", selection: $form.deadlineChoice) {
                Text(keepTitle).tag(TaskEditForm.DeadlineChoice.keep)
                if task.deadline != nil {
                    Text("Remove It").tag(TaskEditForm.DeadlineChoice.remove)
                }
                Text(task.deadline == nil ? "Set One" : "Set a New One").tag(TaskEditForm.DeadlineChoice.set)
            }
            if form.deadlineChoice == .set {
                Toggle("Include a Time", isOn: $form.deadlineIncludesTime)
                DatePicker("Due", selection: $form.deadlineDate, displayedComponents: deadlineComponents)
                    .environment(\.timeZone, form.zone)
            }
        }
    }

    /// The choice that keeps the deadline, naming it.
    private var keepTitle: String {
        task.deadline.map { "Keep: \(TaskText.deadline($0))" } ?? "None"
    }

    /// A day, or a day and a time.
    private var deadlineComponents: DatePickerComponents {
        form.deadlineIncludesTime ? [.date, .hourAndMinute] : [.date]
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
