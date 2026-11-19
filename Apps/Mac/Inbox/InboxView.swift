// The inbox (UI-01): events Lisa found that wait for review and tasks it extracted as possible commitments, each
// confirmed, corrected or dismissed against the version shown, with a recoverable conflict when it changed meanwhile.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The review screen for extracted items and event proposals (UI-01, EVENT-01).
///
/// Every decision goes through `InboxModel`: queued durably with a stable request ID, sent at once when possible, and
/// checked against the revision shown. Saving an event's calendar file never marks it as added; the owner reports that
/// with I Added It once it is on a calendar, because Lisa never writes to a calendar. Command-Return confirms the
/// selected item, Command-E corrects it, Command-Delete dismisses it, and Command-R reads the inbox again.
struct InboxView: View {
    let model: InboxModel

    /// The item a correction sheet is open for.
    private enum Editing: Hashable, Identifiable {
        case proposal(String)
        case task(String)

        var id: Self { self }
    }

    @State private var selection: String?
    @State private var editing: Editing?
    @State private var exportedFile: CalendarFileDocument?
    @State private var isExporting = false
    @State private var exportNote: String?

    var body: some View {
        LoadStateView(
            state: model.proposals, emptyTitle: "Nothing to Review", emptySystemImage: "tray",
            emptyMessage: InboxModel.emptyMessage, isEmpty: { _ in model.isEmpty },
            retry: { await model.load() },
            content: { _ in list }
        )
        .navigationTitle("Inbox")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Confirm", systemImage: "checkmark") {
                    Task { await confirmSelection() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canConfirmSelection)
                .help("Confirms the selected item.")
                Button("Correct…", systemImage: "pencil") { correctSelection() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(selectedProposal == nil && selectedTask == nil)
                Button("Dismiss", systemImage: "xmark") {
                    Task { await dismissSelection() }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedProposal == nil && selectedTask == nil)
                .help("Dismisses the selected item. A dismissed task is cancelled.")
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.proposals.isLoading)
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .proposal(let id):
                if let proposal = model.proposal(id: id) {
                    ProposalCorrectionSheet(model: model, proposal: proposal)
                }
            case .task(let id):
                if let task = model.task(id: id) {
                    TaskCorrectionSheet(model: model, task: task)
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting, document: exportedFile, contentType: .calendarEvent,
            defaultFilename: "Lisa event.ics"
        ) { result in
            switch result {
            case .success:
                exportNote = "Saved. Once the event is on your calendar, choose I Added It."
            case .failure(let error):
                exportNote = "The calendar file wasn't saved: \(error.localizedDescription)"
            }
        }
        .task {
            if case .idle = model.proposals { await model.load() }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if model.isIncomplete {
                Label(
                    "Lisa shows the first items only. Review these, then refresh to see more.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }
            if let outcome = model.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
            if let failure = model.calendarFileFailure {
                Label(MacFailureText.message(of: failure), systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            if let exportNote {
                Label(exportNote, systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }
            Section("Events to Review") {
                if model.proposalsToReview.isEmpty {
                    Text("No events wait for review.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.proposalsToReview, id: \.id) { proposal in
                    ProposalRow(
                        model: model, proposal: proposal, correct: { editing = .proposal(proposal.id) },
                        saveFile: { Task { await saveCalendarFile(proposal) } }
                    )
                    .tag(proposal.id)
                }
            }
            Section("Possible Tasks") {
                InlineLoadState(
                    state: model.tasks, emptyMessage: "No extracted tasks wait for review.",
                    isEmpty: { _ in model.tasksToReview.isEmpty }, retry: { await model.load() },
                    content: { _ in
                        ForEach(model.tasksToReview, id: \.id) { task in
                            ExtractedTaskRow(model: model, task: task, correct: { editing = .task(task.id) })
                                .tag(task.id)
                        }
                    })
            }
        }
    }

    // MARK: - Selection

    private var selectedProposal: EventProposalDTO? {
        selection.flatMap { id in model.proposalsToReview.first { $0.id == id } }
    }

    private var selectedTask: TaskDTO? {
        selection.flatMap { id in model.tasksToReview.first { $0.id == id } }
    }

    private var canConfirmSelection: Bool {
        if let selectedProposal { return InboxModel.canConfirmMatch(selectedProposal) }
        return selectedTask != nil
    }

    private var subtitle: String {
        let count = model.reviewCount
        return count == 1 ? "1 item to review" : "\(count) items to review"
    }

    private func confirmSelection() async {
        if let selectedProposal {
            await model.confirmMatch(selectedProposal)
        } else if let selectedTask {
            await model.confirm(selectedTask)
        }
    }

    private func correctSelection() {
        if let selectedProposal {
            editing = .proposal(selectedProposal.id)
        } else if let selectedTask {
            editing = .task(selectedTask.id)
        }
    }

    private func dismissSelection() async {
        if let selectedProposal {
            await model.dismiss(selectedProposal)
        } else if let selectedTask {
            await model.dismiss(selectedTask)
        }
    }

    /// Reads the proposal's calendar file from the host and offers to save it.
    private func saveCalendarFile(_ proposal: EventProposalDTO) async {
        exportNote = nil
        guard let text = await model.calendarFile(for: proposal) else { return }
        exportedFile = CalendarFileDocument(text: text)
        isExporting = true
    }
}
