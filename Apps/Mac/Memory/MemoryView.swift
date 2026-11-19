// The memory screen (UI-01, MEM-01): the owner's preferences by group, the inferred ones that wait for confirmation,
// and setting, confirming and deleting them through the durable queue.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The owner's preferences (UI-01: inspect and edit preferences). Inferred preferences take effect only once the owner
/// confirms them. Preferences that say who Lisa may contact and how are on Settings and Health with the delivery modes.
/// Command-E edits the selected preference and Command-R reads them again.
struct MemoryView: View {
    let model: MemoryModel

    @State private var selection: String?
    @State private var editingKey: String?

    /// The groups this screen shows; delivery preferences are on Settings and Health.
    private static let groups = PreferenceDescriptor.Group.allCases.filter { $0 != .delivery }

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "No Preferences", emptySystemImage: "brain",
            emptyMessage: MemoryModel.emptyMessage, isEmpty: { _ in false },
            retry: { await model.load() },
            content: { _ in list }
        )
        .navigationTitle("Memory")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu(
                    content: { addMenu },
                    label: { Label("Add Preference", systemImage: "plus") }
                )
                .disabled(unsetKeys.isEmpty)
                Button("Edit…", systemImage: "pencil") { editingKey = selection }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(selection == nil)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
        .sheet(isPresented: isEditing) {
            if let editingKey {
                PreferenceEditSheet(model: model, key: editingKey)
            }
        }
        .task {
            if case .idle = model.state { await model.load() }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if let outcome = model.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
            if model.preferences.isEmpty {
                Text(MemoryModel.emptyMessage)
                    .foregroundStyle(.secondary)
            }
            if !model.inferredAwaitingConfirmation.isEmpty {
                Section("Waiting for Your Confirmation") {
                    ForEach(model.inferredAwaitingConfirmation, id: \.key) { preference in
                        PreferenceRow(model: model, preference: preference, edit: { editingKey = preference.key })
                            .tag(preference.key)
                    }
                }
            }
            ForEach(Self.groups, id: \.self) { group in
                let preferences = model.preferences(in: group).filter { !isAwaitingConfirmation($0) }
                if !preferences.isEmpty {
                    Section(group.title) {
                        ForEach(preferences, id: \.key) { preference in
                            PreferenceRow(model: model, preference: preference, edit: { editingKey = preference.key })
                                .tag(preference.key)
                        }
                    }
                }
            }
            Section {
                Text("Who Lisa may contact and how is on Settings and Health, with the delivery modes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addMenu: some View {
        ForEach(Self.groups, id: \.self) { group in
            let keys = unsetKeys.filter { $0.group == group }
            if !keys.isEmpty {
                Section(group.title) {
                    ForEach(keys, id: \.key) { descriptor in
                        Button(descriptor.title) { editingKey = descriptor.key }
                    }
                }
            }
        }
    }

    /// The known keys outside the delivery group that have no stored preference.
    private var unsetKeys: [PreferenceDescriptor] {
        PreferenceDescriptor.known.filter { $0.group != .delivery && model.preference(key: $0.key) == nil }
    }

    private func isAwaitingConfirmation(_ preference: PreferenceDTO) -> Bool {
        preference.origin == "inferred" && !preference.confirmed
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { editingKey != nil },
            set: { shown in if !shown { editingKey = nil } })
    }
}
