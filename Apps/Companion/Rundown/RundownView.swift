// The rundown screen (UI-02): the plan for today, or the saved copy with its age while the host can't be reached; the
// owner's actions on its blocks; and the rundown read aloud.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Today's planned blocks in time order, what could not be scheduled, and the planner's notes. The host is the only
/// scheduler (UI-02): the owner's decisions on its blocks go to the host through `RundownModel`, saved on this device
/// first while the host can't be reached, and an action the host refused because the plan changed is listed at the top
/// until the owner applies it again or discards it.
///
/// Reading aloud speaks `RundownModel.speechText(at:locale:)`, which starts with the rundown's day and age whenever it
/// is not the host's current answer, so a saved copy is never read out as current. Speech runs only while the app is in
/// use.
struct RundownView: View {
    let model: RundownModel
    /// The app's one speaker, which the brief screen uses too.
    let speaker: BriefSpeaker?

    /// A rundown screen over `model`. Reading aloud uses `speaker`, or else the session's, the one the brief screen
    /// uses, so one reading replaces the other and the session stops it when this device is removed.
    init(model: RundownModel, speaker: BriefSpeaker? = nil) {
        self.model = model
        self.speaker = speaker ?? CompanionSession.shared.models?.speaker
    }

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "Nothing Planned", emptySystemImage: "calendar",
            emptyMessage: "Lisa has no plan for this day yet.",
            isEmpty: { $0.blocks.isEmpty && $0.unscheduled.isEmpty }, isEarlierDay: model.showsEarlierDay,
            retry: { await model.refresh() },
            content: { result in plan(result.value) }
        )
        .navigationTitle("Rundown")
        .refreshable { [model] in await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let speaker {
                    Button(
                        speaker.isSpeaking ? "Stop Reading" : "Read Aloud",
                        systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2"
                    ) {
                        toggleReading(with: speaker)
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!speaker.isSpeaking && model.state.result == nil)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
    }

    private func plan(_ rundown: RundownDTO) -> some View {
        let zone = TimeZone(identifier: rundown.zone) ?? .current
        let refused = model.blockConflicts.values.sorted { $0.blockID < $1.blockID }
        return List {
            if let outcome = model.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
            if !refused.isEmpty {
                Section("Your Change Wasn't Applied") {
                    ForEach(refused, id: \.blockID) { refusal in
                        conflictRow(refusal)
                    }
                }
            }
            Section(LocalDayText.words(for: rundown.date, style: .complete)) {
                if rundown.blocks.isEmpty {
                    Text("Nothing is planned for this day.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rundown.blocks.sorted(by: { $0.start < $1.start }), id: \.blockID) { block in
                    PlanBlockRow(block: block, zone: zone, model: model)
                }
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
            if !rundown.changes.isEmpty {
                Section("What Changed") {
                    ForEach(rundown.changes, id: \.self) { change in
                        Text(change)
                    }
                }
            }
        }
    }

    /// A block action the host refused, with the block as the plan shown has it, to apply again or discard.
    private func conflictRow(_ refusal: PlanBlockConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.title(of: refusal))
                .font(.headline)
            Text("\(PlanBlockActions.label(for: refusal.action)) wasn't applied.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ConflictNotice(
                message: refusal.conflict.message, canApplyAgain: refusal.canApplyAgain,
                applyAgain: { await model.applyAgain(blockID: refusal.blockID) },
                discard: { await model.discardAction(blockID: refusal.blockID) })
        }
    }

    /// The block a refused action was for, as the plan shown names it.
    private static func title(of refusal: PlanBlockConflict) -> String {
        guard let block = refusal.current else { return "A block no longer in the plan" }
        return block.title.isEmpty ? "Untitled block" : block.title
    }

    /// Reads the rundown shown aloud, or stops reading.
    private func toggleReading(with speaker: BriefSpeaker) {
        if speaker.isSpeaking {
            speaker.stop()
        } else if let text = model.speechText(at: Date()) {
            speaker.speak(text)
        }
    }
}
