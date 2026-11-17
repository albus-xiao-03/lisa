// The capture screen (UI-02, UI-03, NEWS-04): an idea, text or a link for a future brief, saved on this device first
// so nothing is lost while the host can't be reached.

import LisaAPIContract
import LisaPresentation
import SwiftUI

/// Captures ideas and items for a future brief. Saving writes the capture to the durable queue and sends it when the
/// host can be reached; the outcome says which happened, and a capture kept for later is never shown as saved in
/// Lisa. Command-Return saves.
struct CaptureView: View {
    @Bindable var model: CaptureModel

    /// The kinds offered here; shares from Apple News arrive through Siri and Shortcuts.
    private static let kinds: [CaptureKindValue] = [.idea, .text, .link]

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $model.draft.kind) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        Text(CaptureDraft(kind: kind).label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(textTitle) {
                TextField(textPrompt, text: $model.draft.text, axis: .vertical)
                    .lineLimit(3...12)
            }
            Section(linkTitle) {
                TextField("https://", text: $model.draft.url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if model.draft.kind == .link {
                    TextField("Title (optional)", text: $model.draft.title)
                }
            }
            if !model.validationIssues.isEmpty {
                Section {
                    ForEach(model.validationIssues, id: \.self) { issue in
                        Label(issue.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button(action: save) {
                    if model.isSubmitting {
                        ProgressView()
                    } else {
                        Label("Save for Lisa", systemImage: "tray.and.arrow.down")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isSubmitting)
                if let outcome = model.lastOutcome {
                    ActionOutcomeLabel(outcome: outcome)
                }
                if model.pendingCaptureCount > 0 {
                    Label(pendingText, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Capture")
        .scrollDismissesKeyboard(.interactively)
    }

    private var textTitle: String {
        model.draft.kind == .link ? "Note (Optional)" : model.draft.label
    }

    private var linkTitle: String {
        model.draft.kind == .link ? "Link" : "Link (Optional)"
    }

    private var textPrompt: String {
        switch model.draft.kind {
        case .idea: "What's the idea?"
        case .text: "Text to keep for a future brief"
        case .link, .sharedAppleNews: "Why it's worth reading"
        }
    }

    private var pendingText: String {
        let count = model.pendingCaptureCount
        return count == 1
            ? "1 capture waits for your Lisa host." : "\(count) captures wait for your Lisa host."
    }

    private func save() {
        Task { await model.submit() }
    }
}
