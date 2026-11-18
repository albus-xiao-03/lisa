// The brief screen (UI-02): the latest brief, or the saved copy with its age, read aloud on request, with earlier
// days' briefs one day at a time.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The brief as the host composed it, and "read the brief" (SIRI-02: the brief is spoken).
///
/// Reading aloud speaks `BriefModel.speechText(at:)`, which starts with a notice when the brief is a saved copy, so a
/// stale brief is never read out as current. Speech runs only while the app is in use. Preparing the brief again is a
/// direct request to the host, so it is unavailable while the host can't be reached; its outcome is shown.
struct BriefView: View {
    let model: BriefModel
    let speaker: BriefSpeaker

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "No Brief Yet", emptySystemImage: "newspaper",
            emptyMessage: "Lisa hasn't prepared a brief for this day.", isEmpty: { $0.text.isEmpty },
            isEarlierDay: model.showsEarlierDay, retry: { await model.refresh() },
            content: { result in brief(result.value) }
        )
        .navigationTitle("Brief")
        .refreshable { [model] in await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(readTitle, systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2") {
                    toggleReading()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!speaker.isSpeaking && model.spokenText == nil)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
                Menu(
                    content: { moreActions },
                    label: { Label("More", systemImage: "ellipsis.circle") })
            }
        }
    }

    private func brief(_ brief: BriefDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prepared \(brief.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let status = model.statusMessage {
                    Label(status, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let outcome = model.lastRegeneration {
                    ActionOutcomeLabel(outcome: outcome)
                }
                Text(brief.text)
                    .textSelection(.enabled)
                if let omitted = brief.omittedItems, !omitted.isEmpty {
                    // The full view of the items left out to keep the brief short (BRIEF-04).
                    DisclosureGroup("Left Out to Keep It Short (\(omitted.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(omitted.enumerated()), id: \.offset) { entry in
                                Text(entry.element.text)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    private var moreActions: some View {
        Button("Previous Day", systemImage: "chevron.backward") {
            guard let day = model.previousDate else { return }
            Task { await model.load(date: day) }
        }
        .disabled(model.previousDate == nil)
        Button("Next Day", systemImage: "chevron.forward") {
            guard let day = model.nextDate else { return }
            Task { await model.load(date: day) }
        }
        .disabled(model.nextDate == nil)
        Button("Today's Brief", systemImage: "calendar") {
            Task { await model.load(date: nil) }
        }
        .disabled(model.date == nil)
        Divider()
        Button("Prepare Again", systemImage: "arrow.triangle.2.circlepath") {
            Task { await model.regenerate() }
        }
        .disabled(model.isRegenerating)
    }

    private var readTitle: String {
        speaker.isSpeaking ? "Stop Reading" : "Read Aloud"
    }

    private func toggleReading() {
        if speaker.isSpeaking {
            speaker.stop()
        } else if let text = model.speechText(at: Date()) {
            speaker.speak(text)
        }
    }
}
