// The capture field on Today (UI-01 quick actions, UI-03): an idea, text or a link for a future brief, saved on this
// Mac first through the durable queue, with the truthful outcome.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Captures an idea, text or a link with one line. Return saves; New Capture (Command-N) puts the cursor here. The
/// outcome says whether Lisa's host has the capture or it waits on this Mac; a capture kept for later is never shown as
/// saved in Lisa.
struct QuickCaptureBar: View {
    @Bindable var model: CaptureModel
    @Bindable var navigation: MacNavigation
    @FocusState private var isFocused: Bool

    /// The kinds offered here; shares from Apple News arrive through Siri and Shortcuts.
    private static let kinds: [CaptureKindValue] = [.idea, .text, .link]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Kind", selection: $model.draft.kind) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        Text(CaptureDraft(kind: kind).label).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Kind of capture")
                TextField(prompt, text: model.draft.kind == .link ? $model.draft.url : $model.draft.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(save)
                    .accessibilityLabel(prompt)
                Button("Save", action: save)
                    .disabled(model.isSubmitting)
            }
            ForEach(model.validationIssues, id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let outcome = model.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
            if model.pendingCaptureCount > 0 {
                Label(pendingText, systemImage: "clock.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: navigation.wantsCaptureFocus, initial: true) { _, wants in
            guard wants else { return }
            isFocused = true
            navigation.wantsCaptureFocus = false
        }
    }

    private var prompt: String {
        switch model.draft.kind {
        case .idea: "Capture an idea"
        case .text: "Text to keep for a future brief"
        case .link, .sharedAppleNews: "A link to read later (https://…)"
        }
    }

    private var pendingText: String {
        let count = model.pendingCaptureCount
        return count == 1 ? "1 capture waits for Lisa's host." : "\(count) captures wait for Lisa's host."
    }

    private func save() {
        Task { await model.submit() }
    }
}
