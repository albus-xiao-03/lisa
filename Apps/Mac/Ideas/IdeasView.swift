// The ideas screen (UI-01): capturing ideas through the durable queue, and editing, prioritizing, offering for
// planning and archiving them against the version shown, with a recoverable conflict when one changed meanwhile.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Ideas from the host, optionally of one stage (UI-01, IDEA-01). Offering an idea for planning lets the host's planner
/// propose a block for it; it becomes scheduled when that block is accepted. Idea changes are sent directly, so while
/// the host can't be reached they are reported as unavailable and nothing is kept. Command-E edits the selected idea,
/// Command-Shift-P offers it for planning and Command-R reads the list again; Archive has no shortcut, so that
/// Command-Delete keeps editing text in the capture field.
struct IdeasView: View {
    let model: IdeasModel

    @State private var selection: String?
    @State private var editingID: String?

    var body: some View {
        VStack(spacing: 0) {
            captureBar
                .padding()
            Divider()
            LoadStateView(
                state: model.state, emptyTitle: "No Ideas", emptySystemImage: "lightbulb",
                emptyMessage: IdeasModel.emptyMessage, isEmpty: { $0.items.isEmpty },
                retry: { await model.refresh() },
                content: { _ in list }
            )
        }
        .navigationTitle("Ideas")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Show", selection: filter) {
                    Text("All Ideas").tag(IdeaLifecycleValue?.none)
                    ForEach(IdeaLifecycleValue.allCases, id: \.self) { stage in
                        Text(IdeasModel.label(for: stage)).tag(Optional(stage))
                    }
                }
                .pickerStyle(.menu)
                .help("Shows the ideas of one stage.")
                Button("Edit…", systemImage: "pencil") { editingID = selectedIdea?.id }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(selectedIdea == nil)
                Button("Offer for Planning", systemImage: "calendar.badge.plus") {
                    guard let idea = selectedIdea else { return }
                    Task { await model.offerForPlanning(idea) }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!canOfferSelection)
                Button("Archive", systemImage: "archivebox") {
                    guard let idea = selectedIdea else { return }
                    Task { await model.archive(idea) }
                }
                .disabled(!canArchiveSelection)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
        .sheet(isPresented: isEditing) {
            if let editingID, let idea = model.idea(id: editingID) {
                IdeaEditSheet(model: model, idea: idea)
            }
        }
        .task {
            if case .idle = model.state { await model.load() }
        }
    }

    private var captureBar: some View {
        @Bindable var capture = model.capture
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Capture a new idea", text: $capture.draft.text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(captureIdea)
                Button("Capture", action: captureIdea)
                    .disabled(capture.isSubmitting)
            }
            ForEach(capture.validationIssues, id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let outcome = capture.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if let outcome = model.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
            ForEach(model.ideas, id: \.id) { idea in
                IdeaRow(model: model, idea: idea, edit: { editingID = idea.id })
                    .tag(idea.id)
            }
            if model.hasMore {
                Button("Show More Ideas") {
                    Task { await model.loadMore() }
                }
                .disabled(model.isLoadingMore)
            }
        }
    }

    // MARK: - Selection and filter

    private var selectedIdea: IdeaDTO? {
        selection.flatMap { model.idea(id: $0) }
    }

    private var canOfferSelection: Bool {
        guard let idea = selectedIdea else { return false }
        return IdeasModel.stages(after: idea.lifecycle).contains(.availableForPlanning)
    }

    private var canArchiveSelection: Bool {
        guard let idea = selectedIdea else { return false }
        return IdeasModel.stages(after: idea.lifecycle).contains(.archived)
    }

    private var filter: Binding<IdeaLifecycleValue?> {
        Binding(
            get: { model.lifecycleFilter },
            set: { stage in Task { await model.load(lifecycle: stage) } })
    }

    private var isEditing: Binding<Bool> {
        Binding(
            get: { editingID != nil },
            set: { shown in if !shown { editingID = nil } })
    }

    private func captureIdea() {
        Task { await model.captureIdea() }
    }
}
