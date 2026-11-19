// The truthful result of an action, as one line: done, saved for later, unavailable, changed on the host, or failed.

import LisaPresentation
import SwiftUI

/// Shows an `ActionOutcome` with its sentence (UI-03). A queued action reads as saved for later, never as done.
struct ActionOutcomeLabel: View {
    let outcome: ActionOutcome

    var body: some View {
        Label(
            title: { Text(outcome.summary) },
            icon: { Image(systemName: symbol).foregroundStyle(symbolColor) }
        )
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch outcome {
        case .done: "checkmark.circle"
        case .queued: "clock.arrow.circlepath"
        case .unavailable: "bolt.horizontal.circle"
        case .conflict: "exclamationmark.triangle"
        case .failed: "xmark.octagon"
        }
    }

    private var symbolColor: Color {
        switch outcome {
        case .done: .green
        case .queued: .secondary
        case .unavailable, .conflict: .orange
        case .failed: .red
        }
    }
}
