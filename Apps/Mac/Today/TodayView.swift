// Today (UI-01): the day's commitments and suggested blocks from the rundown with the owner's actions on them, the
// open tasks with completing them, and quick actions: a capture, the brief read aloud, and the items waiting in the
// inbox.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The daily view. The plan comes from the host, which is the only scheduler; the screen shows it and acts only through
/// the view models: capturing through the durable queue, deciding on the plan's blocks against the plan revision
/// shown, and completing or reopening a task against the version shown. A block action the host refused because the
/// plan changed is listed until the owner applies it again or discards it. Command-Return completes the selected task,
/// Command-R reads everything again, and Command-Shift-R reads the brief aloud.
struct TodayView: View {
    let models: MacModels
    @Bindable var navigation: MacNavigation
    @State private var selectedTaskID: String?

    var body: some View {
        List(selection: $selectedTaskID) {
            Section("Quick Actions") {
                QuickCaptureBar(model: models.capture, navigation: navigation)
                quickActions
            }
            refusedBlockActions
            commitmentsSection
            if let rundown = models.rundown.state.value {
                planNotes(rundown)
            }
            tasksSection
        }
        .navigationTitle("Today")
        .navigationSubtitle(Date().formatted(date: .complete, time: .omitted))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Complete Selected Task", systemImage: "checkmark.circle") {
                    guard let task = selectedTask else { return }
                    Task { await models.tasks.complete(task) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedTask == nil || selectedTask?.status == .completed)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(models.rundown.state.isLoading)
            }
        }
        .task {
            if case .idle = models.rundown.state { await models.rundown.load() }
            if case .idle = models.tasks.state { await models.tasks.load(status: .open) }
            if case .idle = models.inbox.proposals { await models.inbox.load() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(
                models.speaker.isSpeaking ? "Stop Reading" : "Read the Brief Aloud",
                systemImage: models.speaker.isSpeaking ? "stop.fill" : "speaker.wave.2"
            ) {
                Task { await toggleReading() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open the Brief", systemImage: "newspaper") { navigation.show(.brief) }
            Button(inboxTitle, systemImage: "tray") { navigation.show(.inbox) }
                .disabled(models.inbox.reviewCount == 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var commitmentsSection: some View {
        Section("Commitments") {
            InlineLoadState(
                state: models.rundown.state, emptyMessage: "Lisa has no plan for today yet.", isEmpty: { _ in false },
                isEarlierDay: models.rundown.showsEarlierDay, retry: { await models.rundown.refresh() },
                content: { result in
                    let zone = TimeZone(identifier: result.value.zone) ?? .current
                    let commitments = Self.commitments(in: result.value)
                    if commitments.isEmpty {
                        Text("Nothing is planned for today.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(commitments, id: \.blockID) { block in
                        PlanBlockRow(block: block, zone: zone, model: models.rundown)
                    }
                })
            if let outcome = models.rundown.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
        }
    }

    /// The block actions the host refused because the plan changed, each with the block as the plan shown has it, to
    /// apply again or discard.
    @ViewBuilder
    private var refusedBlockActions: some View {
        let refused = models.rundown.blockConflicts.values.sorted { $0.blockID < $1.blockID }
        if !refused.isEmpty {
            Section("Not Applied to the Plan") {
                ForEach(refused, id: \.blockID) { refusal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.title(of: refusal))
                            .font(.headline)
                        Text("\(PlanBlockActions.label(for: refusal.action)) wasn't applied.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ConflictNotice(
                            message: refusal.conflict.message, canApplyAgain: refusal.canApplyAgain,
                            applyAgain: { await models.rundown.applyAgain(blockID: refusal.blockID) },
                            discard: { await models.rundown.discardAction(blockID: refusal.blockID) })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planNotes(_ rundown: RundownDTO) -> some View {
        let zone = TimeZone(identifier: rundown.zone) ?? .current
        let suggested = Self.suggestions(in: rundown)
        if !suggested.isEmpty {
            Section(
                content: {
                    ForEach(suggested, id: \.blockID) { block in
                        PlanBlockRow(block: block, zone: zone, model: models.rundown)
                    }
                },
                header: { Text("Suggested Blocks") },
                footer: {
                    Text(
                        "Lisa suggests these. Accept one to keep it in your plan, or lock it to keep its time when "
                            + "Lisa plans again. Declining one stops Lisa suggesting it until something relevant "
                            + "changes."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                })
        }
        if !rundown.unscheduled.isEmpty {
            Section("Couldn't Be Scheduled") {
                ForEach(rundown.unscheduled, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if rundown.availabilityUncertain || !rundown.warnings.isEmpty {
            Section("Notes") {
                if rundown.availabilityUncertain {
                    Label(
                        "Some calendar information is missing, so times may change.",
                        systemImage: "calendar.badge.exclamationmark")
                }
                ForEach(rundown.warnings, id: \.self) { warning in
                    Text(warning)
                }
            }
        }
    }

    private var tasksSection: some View {
        Section("Open Tasks") {
            InlineLoadState(
                state: models.tasks.state, emptyMessage: "No open tasks.", isEmpty: { $0.items.isEmpty },
                retry: { await models.tasks.refresh() },
                content: { result in
                    ForEach(result.value.items, id: \.id) { task in
                        TodayTaskRow(task: task, model: models.tasks)
                            .tag(task.id)
                    }
                })
            if models.tasks.hasMore {
                Button("Show More Tasks") {
                    Task { await models.tasks.loadMore() }
                }
                .disabled(models.tasks.isLoadingMore)
            }
            if let outcome = models.tasks.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
        }
    }

    // MARK: - Actions and words

    private var selectedTask: TaskDTO? {
        selectedTaskID.flatMap { models.tasks.task(id: $0) }
    }

    private var inboxTitle: String {
        let count = models.inbox.reviewCount
        switch count {
        case 0: return "Nothing to Review"
        case 1: return "Review 1 Item"
        default: return "Review \(count) Items"
        }
    }

    private func refresh() async {
        await models.rundown.refresh()
        await models.tasks.refresh()
        await models.inbox.load()
    }

    /// Reads the brief aloud, reading it from the host first when it was not read yet; stops when it is being read.
    private func toggleReading() async {
        if models.speaker.isSpeaking {
            models.speaker.stop()
            return
        }
        if models.brief.state.value == nil { await models.brief.load() }
        if let text = models.brief.speechText(at: Date()) { models.speaker.speak(text) }
    }

    /// The block a refused action was for, as the plan shown names it.
    private static func title(of refusal: PlanBlockConflict) -> String {
        guard let block = refusal.current else { return "A block no longer in the plan" }
        return block.title.isEmpty ? "Untitled block" : block.title
    }

    /// The blocks the day is committed to, in time order: everything but suggestions and the blocks declined or
    /// deferred.
    private static func commitments(in rundown: RundownDTO) -> [PlanBlockDTO] {
        let committed = rundown.blocks.filter { !["proposed", "rejected", "deferred"].contains($0.state) }
        return committed.sorted { $0.start < $1.start }
    }

    /// The planner's suggestions, in time order.
    private static func suggestions(in rundown: RundownDTO) -> [PlanBlockDTO] {
        rundown.blocks.filter { $0.state == "proposed" }.sorted { $0.start < $1.start }
    }
}
