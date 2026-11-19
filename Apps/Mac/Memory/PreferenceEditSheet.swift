// The edit sheet of one preference: a switch for on-or-off values, otherwise the value as text in the form its key
// takes, sent against the version the owner saw.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Sets one preference (MEM-01). The text is read in the form of the key (`PreferenceDescriptor.value(fromText:as:)`);
/// the host checks the value and stays the authority, and its refusal is shown on the preference's row. A change kept
/// for later closes the sheet like one the host applied, and the row shows it waiting.
struct PreferenceEditSheet: View {
    let model: MemoryModel
    let key: String

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var flag: Bool
    @State private var problem: String?
    @State private var outcome: ActionOutcome?
    @State private var isSaving = false

    /// A sheet that sets `key` through `model`, starting from the value shown.
    init(model: MemoryModel, key: String) {
        self.model = model
        self.key = key
        let shown = model.displayedValue(for: key)
        _text = State(initialValue: shown.map(PreferenceDescriptor.displayText) ?? "")
        if case .flag(let value)? = shown {
            _flag = State(initialValue: value)
        } else {
            _flag = State(initialValue: false)
        }
    }

    var body: some View {
        Form {
            Section(descriptor.title) {
                if descriptor.kind == .flag {
                    Toggle(descriptor.title, isOn: $flag)
                } else {
                    TextField("Value", text: $text, axis: .vertical)
                        .lineLimit(1...6)
                    if let hint = descriptor.hint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if descriptor.kind == .list {
                        Text("Separate entries with commas or new lines.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Key", value: key)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .frame(minWidth: 420, minHeight: 260)
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

    private var descriptor: PreferenceDescriptor { PreferenceDescriptor.describing(key) }

    private func save() async {
        let value: PreferenceValueDTO
        if descriptor.kind == .flag {
            value = .flag(flag)
        } else if let parsed = PreferenceDescriptor.value(fromText: text, as: descriptor.kind) {
            value = parsed
        } else {
            problem =
                descriptor.kind == .number ? "Enter a number." : "Enter a value; an empty value isn't saved."
            return
        }
        problem = nil
        isSaving = true
        defer { isSaving = false }
        let result = await model.set(key, to: value)
        outcome = result
        if result.isDone || result.isQueued { dismiss() }
    }
}
