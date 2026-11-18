// The correction sheet of an event proposal: its title, a new time or day, and its place, sent as one correction
// against the version the owner saw.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Corrects an event proposal (EVENT-01: the owner corrects a proposal). Only the fields the owner changed are sent; the
/// timing stays as it is unless the owner sets a new time or day. A correction kept for later closes the sheet like
/// one the host applied, and the row shows it waiting.
struct ProposalCorrectionSheet: View {
    let model: InboxModel
    let proposal: EventProposalDTO

    /// What happens to the proposal's timing.
    private enum TimingChoice: Hashable {
        case keep
        case time
        case day
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var location: String
    @State private var timingChoice = TimingChoice.keep
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var day: Date
    @State private var problem: String?
    @State private var outcome: ActionOutcome?
    @State private var isSaving = false

    /// A sheet that corrects `proposal` through `model`, starting from the proposal as shown.
    init(model: InboxModel, proposal: EventProposalDTO) {
        self.model = model
        self.proposal = proposal
        let start = proposal.timing.start ?? Date()
        _title = State(initialValue: proposal.title)
        _location = State(initialValue: proposal.location ?? "")
        _start = State(initialValue: start)
        _hasEnd = State(initialValue: proposal.timing.end != nil)
        _end = State(initialValue: proposal.timing.end ?? start.addingTimeInterval(3_600))
        _day = State(initialValue: start)
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                TextField("Place", text: $location)
            }
            Section("When") {
                Picker("Timing", selection: $timingChoice) {
                    Text("Keep as it is").tag(TimingChoice.keep)
                    Text("Set a time").tag(TimingChoice.time)
                    Text("Set a day (all day)").tag(TimingChoice.day)
                }
                switch timingChoice {
                case .keep:
                    EmptyView()
                case .time:
                    DatePicker("Starts", selection: $start)
                    Toggle("Has an end time", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $end, in: start...)
                    }
                case .day:
                    DatePicker("Day", selection: $day, displayedComponents: .date)
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
        .frame(minWidth: 440, minHeight: 340)
        .navigationTitle("Correct Event")
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

    /// The correction of the fields the owner changed.
    private var correction: ProposalCorrection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let timing: ProposedTimingDTO? =
            switch timingChoice {
            case .keep: nil
            case .time: ProposedTimingDTO(start: start, end: hasEnd ? end : nil, zone: TimeZone.current.identifier)
            case .day: ProposedTimingDTO(date: LocalDayText.localDate(of: day))
            }
        return ProposalCorrection(
            title: trimmedTitle == proposal.title ? nil : trimmedTitle, timing: timing,
            location: trimmedLocation.isEmpty || trimmedLocation == proposal.location ? nil : trimmedLocation)
    }

    private func save() async {
        let correction = correction
        if let issue = correction.problem {
            problem = issue
            return
        }
        problem = nil
        isSaving = true
        defer { isSaving = false }
        let result = await model.correct(proposal, correction)
        outcome = result
        if result.isDone || result.isQueued { dismiss() }
    }
}
