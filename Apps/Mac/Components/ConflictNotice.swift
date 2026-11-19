// A recoverable conflict (UI-03): the owner's change was refused because the item changed on the host, and the owner
// chooses to apply it again to the current version or to discard it.

import SwiftUI

/// Shows an action the host refused because its subject changed meanwhile. Nothing is applied until the owner chooses;
/// when the change can no longer be applied, only discarding is offered.
struct ConflictNotice: View {
    /// The host's explanation, without private content.
    let message: String
    /// Whether the change can be applied to the item's current version.
    let canApplyAgain: Bool
    /// Applies the change again to the current version.
    let applyAgain: @MainActor () async -> Void
    /// Discards the change; the item stays as the host has it.
    let discard: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("This changed on Lisa's host after you acted on it.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Apply Again", systemImage: "arrow.clockwise") {
                    Task { await applyAgain() }
                }
                .disabled(!canApplyAgain)
                .accessibilityHint("Sends your change again, to the version now on Lisa's host.")
                Button(
                    role: .destructive, action: { Task { await discard() } },
                    label: { Label("Discard", systemImage: "trash") }
                )
                .accessibilityHint("Keeps the item as Lisa's host has it.")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
