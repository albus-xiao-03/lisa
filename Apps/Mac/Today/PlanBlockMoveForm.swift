// Moving a block of Today's rundown: start and end pickers in the rundown's time zone, and the host's answer.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// The popover that moves a block to a new start and end (PLAN-04), picked to the minute in the rundown's time zone on
/// the block's day. Lisa locks a moved block at its new time and plans the rest of the day around it.
///
/// What the host answers decides what happens next. A move it applied, one saved until the host can be reached, and
/// one refused because the plan changed meanwhile close the popover: the row, and Today's list of actions not applied,
/// show the result. A move the host refuses, for example because the new time would overlap a busy calendar event or
/// a locked block, keeps the popover open with the host's reason, so the owner can pick other times.
struct PlanBlockMoveForm: View {
    let block: PlanBlockDTO
    let zone: TimeZone
    let model: RundownModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var outcome: ActionOutcome?
    @State private var isSending = false

    init(block: PlanBlockDTO, zone: TimeZone, model: RundownModel) {
        self.block = block
        self.zone = zone
        self.model = model
        _start = State(initialValue: block.start)
        _end = State(initialValue: block.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \u{201C}\(title)\u{201D}")
                .font(.headline)
            Form {
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            }
            .environment(\.timeZone, zone)
            Text(
                "Lisa keeps a moved block at its new time when she plans again. It can't overlap a busy calendar "
                    + "event, or a block you accepted, locked or completed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if !picked.isOrdered {
                Label("The end must be after the start.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let outcome {
                ActionOutcomeLabel(outcome: outcome)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var title: String { block.title.isEmpty ? "Untitled block" : block.title }

    /// The times picked, to the minute.
    private var picked: PlanBlockTimes { PlanBlockTimes(start: start, end: end).toTheMinute }

    /// Whether the times picked can be sent: nothing is being sent, the end is after the start, and they differ from
    /// the block's times.
    private var canSubmit: Bool {
        !isSending && picked.isOrdered && picked != PlanBlockTimes(of: block).toTheMinute
    }

    /// Sends the move and keeps the popover open only when the host refused it or nothing could be saved.
    private func submit() async {
        isSending = true
        defer { isSending = false }
        let result = await model.move(block, to: picked)
        switch result {
        case .done, .queued, .conflict:
            dismiss()
        case .failed, .unavailable:
            outcome = result
        }
    }
}
