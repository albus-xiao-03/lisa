// One event proposal in the inbox: what Lisa found, when and where, why it needs review, and confirming, saving,
// correcting or dismissing it, with a mark while a decision waits to sync.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// An event proposal with its review actions (UI-01, EVENT-01).
struct ProposalRow: View {
    let model: InboxModel
    let proposal: EventProposalDTO
    /// Opens the correction sheet.
    let correct: () -> Void
    /// Reads and saves the calendar file.
    let saveFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title.isEmpty ? "Untitled event" : proposal.title)
                    .font(.headline)
                Text(timing)
                    .font(.callout)
                if let location = proposal.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.callout)
                }
                if !proposal.participants.isEmpty {
                    Label(proposal.participants.joined(separator: ", "), systemImage: "person.2")
                        .font(.callout)
                }
                Text(InboxModel.reviewStatus(of: proposal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(proposal.uncertainty, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.proposalConflicts[proposal.id] != nil {
                    SyncBadge(kind: .conflict)
                } else if model.pendingProposalActions[proposal.id] != nil {
                    SyncBadge(kind: .waiting)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                if InboxModel.canConfirmMatch(proposal) {
                    Button("It's on My Calendar") {
                        Task { await model.confirmMatch(proposal) }
                    }
                    .help("Confirms that this is the calendar event Lisa matched it with.")
                }
                if InboxModel.canSaveCalendarFile(proposal) {
                    Button("Save Calendar File…", action: saveFile)
                        .help("Saves the event as a file to add to your calendar yourself.")
                    Button("I Added It") {
                        Task { await model.reportAdded(proposal) }
                    }
                    .help("Tells Lisa you added it; Lisa looks for it when your calendar refreshes.")
                }
                Button("Correct…", action: correct)
                Button(
                    role: .destructive, action: { Task { await model.dismiss(proposal) } },
                    label: { Text("Dismiss") })
                if model.busyItemIDs.contains(proposal.id) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .controlSize(.small)
            .disabled(model.busyItemIDs.contains(proposal.id))
            if let refused = model.proposalConflicts[proposal.id] {
                ConflictNotice(
                    message: refused.conflict.message, canApplyAgain: refused.conflict.canApplyToCurrentRevision,
                    applyAgain: { await model.applyAgain(proposalID: proposal.id) },
                    discard: { await model.discardAction(proposalID: proposal.id) })
            }
        }
        .padding(.vertical, 4)
    }

    /// When the event is, in its own time zone, or that it has no date yet.
    private var timing: String {
        let zone = proposal.timing.zone.flatMap(TimeZone.init(identifier:)) ?? .current
        if let start = proposal.timing.start {
            let style = Date.FormatStyle(date: .complete, time: .shortened, timeZone: zone)
            guard let end = proposal.timing.end else { return start.formatted(style) }
            let endStyle = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
            return "\(start.formatted(style)) – \(end.formatted(endStyle))"
        }
        if let date = proposal.timing.date { return "\(LocalDayText.words(for: date, style: .complete)), all day" }
        return "No date or time yet"
    }
}
