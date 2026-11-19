// One queued action: what it is, how long it has waited, why its last attempt did not go through, and whether the
// host may already have applied it.

import LisaClient
import LisaPresentation
import SwiftUI

/// An entry of the offline queue as the pending-actions screen shows it. Request IDs, attempts and revisions are in
/// Diagnostics.
struct PendingActionRow: View {
    let action: PendingAction

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(action.summary)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .lineLimit(2)
            }
            AgeText(prefix: "Saved", date: action.queuedAt)
                .font(.caption)
                .foregroundStyle(.secondary)
            if action.needsResolution, let message = action.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if action.mayHaveBeenApplied {
                Label(
                    "Your host may already have applied this. Check the item before trying again.",
                    systemImage: "questionmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What a capture says, so the owner can tell captures apart.
    private var detail: String? {
        guard case .capture(let request)? = action.mutation else { return nil }
        return request.text ?? request.url
    }
}
