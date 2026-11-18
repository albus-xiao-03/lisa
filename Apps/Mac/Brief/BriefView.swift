// The brief screen (UI-01): the current brief or an earlier day's, each item with its sources, the regeneration
// status, and reading it aloud; a saved copy is shown with its age while the host can't be reached.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// The brief as the host composed it (UI-01: current and previous briefs, sources, regeneration status).
///
/// Reading aloud speaks `BriefModel.speechText(at:)`, which starts with a notice when the brief is a saved copy or an
/// earlier day's, so a stale brief is never read out as current. Speech runs only while the app is open. Preparing the
/// brief again is a direct request to the host, so it is unavailable while the host can't be reached; its outcome is
/// shown. Command-[ and Command-] step through the days, Command-T returns to today's brief, Command-R reads it again
/// and Command-Shift-R reads it aloud.
struct BriefView: View {
    let model: BriefModel
    let speaker: BriefSpeaker

    var body: some View {
        LoadStateView(
            state: model.state, emptyTitle: "No Brief Yet", emptySystemImage: "newspaper",
            emptyMessage: "Lisa hasn't prepared a brief for this day.",
            isEmpty: { $0.text.isEmpty && $0.items.isEmpty }, isEarlierDay: model.showsEarlierDay,
            retry: { await model.refresh() },
            content: { result in brief(result.value) }
        )
        .navigationTitle("Brief")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous Day", systemImage: "chevron.backward") {
                    guard let day = model.previousDate else { return }
                    Task { await model.load(date: day) }
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model.previousDate == nil)
                Button("Next Day", systemImage: "chevron.forward") {
                    guard let day = model.nextDate else { return }
                    Task { await model.load(date: day) }
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model.nextDate == nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Today's Brief", systemImage: "calendar") {
                    Task { await model.load(date: nil) }
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.date == nil)
                Button(readTitle, systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2") {
                    toggleReading()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!speaker.isSpeaking && model.spokenText == nil)
                Button("Prepare Again", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.regenerate() }
                }
                .disabled(model.isRegenerating)
                .help("Asks Lisa's host to prepare this day's brief again.")
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.state.isLoading)
            }
        }
        .task {
            if case .idle = model.state { await model.load() }
        }
    }

    private func brief(_ brief: BriefDTO) -> some View {
        List {
            Section {
                Text("Prepared \(brief.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let status = model.statusMessage {
                    Label(status, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let outcome = model.lastRegeneration {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
            if brief.items.isEmpty {
                Section {
                    Text(brief.text)
                        .textSelection(.enabled)
                }
            } else {
                ForEach(Self.sections(of: brief), id: \.self) { section in
                    Section(BriefItemRow.title(ofSection: section)) {
                        ForEach(Self.items(of: brief, in: section), id: \.offset) { entry in
                            BriefItemRow(item: entry.element)
                        }
                    }
                }
            }
            if brief.omittedCount > 0 {
                Section {
                    Text(omittedText(brief.omittedCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        guard let shown = model.state.value?.date ?? model.date else { return "" }
        return LocalDayText.words(for: shown, style: .complete)
    }

    private var readTitle: String {
        speaker.isSpeaking ? "Stop Reading" : "Read Aloud"
    }

    private func omittedText(_ count: Int) -> String {
        count == 1
            ? "1 more item was left out to keep the brief short."
            : "\(count) more items were left out to keep the brief short."
    }

    private func toggleReading() {
        if speaker.isSpeaking {
            speaker.stop()
        } else if let text = model.speechText(at: Date()) {
            speaker.speak(text)
        }
    }

    /// The brief's sections in the order its items first use them.
    private static func sections(of brief: BriefDTO) -> [String] {
        var seen: Set<String> = []
        return brief.items.map(\.section).filter { seen.insert($0).inserted }
    }

    /// The items of `section` with their positions in the brief, which identify them on screen.
    private static func items(of brief: BriefDTO, in section: String) -> [(offset: Int, element: BriefItemDTO)] {
        brief.items.enumerated().filter { $0.element.section == section }
    }
}
