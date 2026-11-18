// The edit sheet of an idea: its summary, tags, notes, priority, exploration estimate and deadline, sent as one change
// against the version the owner saw. The owner's original capture is shown and never changed.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Edits an idea (UI-01, IDEA-01). Only the fields the owner changed are sent; the deadline stays as it is unless the
/// owner removes it or sets a new day. While the host can't be reached the change is not kept, so the sheet stays open
/// with the outcome.
struct IdeaEditSheet: View {
    let model: IdeasModel
    let idea: IdeaDTO

    /// What happens to the idea's deadline.
    private enum DeadlineChoice: Hashable {
        case keep
        case remove
        case set
    }

    @Environment(\.dismiss) private var dismiss
    @State private var summary: String
    @State private var tags: String
    @State private var notes: String
    @State private var priority: TaskPriorityValue
    @State private var estimate: String
    @State private var deadlineChoice = DeadlineChoice.keep
    @State private var deadlineDay = Date()
    @State private var problem: String?
    @State private var outcome: ActionOutcome?
    @State private var isSaving = false

    /// A sheet that edits `idea` through `model`, starting from the idea as shown.
    init(model: IdeasModel, idea: IdeaDTO) {
        self.model = model
        self.idea = idea
        _summary = State(initialValue: idea.summary)
        _tags = State(initialValue: idea.tags.joined(separator: ", "))
        _notes = State(initialValue: idea.notes)
        _priority = State(initialValue: idea.priority)
        _estimate = State(initialValue: idea.estimatedMinutes.map(String.init) ?? "")
    }

    var body: some View {
        Form {
            Section("You Wrote") {
                Text(idea.originalCapture)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Idea") {
                TextField("Summary", text: $summary, axis: .vertical)
                    .lineLimit(1...4)
                TextField("Tags, separated by commas", text: $tags)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriorityValue.allCases, id: \.self) { value in
                        Text(TaskText.priority(value)).tag(value)
                    }
                }
                TextField("Time to explore it (minutes)", text: $estimate)
            }
            Section("Deadline") {
                Picker("Deadline", selection: $deadlineChoice) {
                    Text(keepTitle).tag(DeadlineChoice.keep)
                    Text("Remove it").tag(DeadlineChoice.remove)
                    Text("Set a day").tag(DeadlineChoice.set)
                }
                if deadlineChoice == .set {
                    DatePicker("By", selection: $deadlineDay, displayedComponents: .date)
                }
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
        .frame(minWidth: 460, minHeight: 480)
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
        idea.deadline.map { "Keep: \(TaskText.deadline($0))" } ?? "Keep: none"
    }

    private func save() async {
        let trimmedEstimate = estimate.trimmingCharacters(in: .whitespaces)
        var minutes: Int?
        if !trimmedEstimate.isEmpty {
            guard let parsed = Int(trimmedEstimate) else {
                problem = "Enter the time to explore it as a number of minutes."
                return
            }
            minutes = parsed
        }
        var edit = IdeaEdit()
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSummary != idea.summary { edit.summary = trimmedSummary }
        let newTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if newTags != idea.tags { edit.tags = newTags }
        if notes != idea.notes { edit.notes = notes }
        if priority != idea.priority { edit.priority = priority }
        if let minutes, minutes != idea.estimatedMinutes { edit.estimatedMinutes = minutes }
        switch deadlineChoice {
        case .keep: break
        case .remove: edit.clearDeadline = idea.deadline != nil
        case .set: edit.deadline = DeadlineDTO(date: LocalDayText.localDate(of: deadlineDay))
        }
        if let issue = edit.problem {
            problem = issue
            return
        }
        problem = nil
        isSaving = true
        defer { isSaving = false }
        let result = await model.edit(idea, edit)
        outcome = result
        if result.isDone { dismiss() }
    }
}
