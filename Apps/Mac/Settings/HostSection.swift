// Lisa's host on Settings and Health: which host the app uses and why, trying again or restarting it, and the runtime
// state the host reports: its status, how long it has run, the last processing cycle, warnings and deliveries.

import Foundation
import LisaPresentation
import SwiftUI

/// The host's mode and runtime state (UI-01: runtime state). Versions and identifiers are in Diagnostics.
struct HostSection: View {
    let session: MacSession
    let settings: SettingsHealthModel

    var body: some View {
        Section("Lisa's Host") {
            LabeledContent("Mode") {
                Label(mode.title, systemImage: mode.systemImage)
            }
            Text(mode.message)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                if mode.canRetry {
                    Button("Try Again") {
                        Task { await session.retryHost() }
                    }
                }
                if mode.isEmbedded {
                    Button("Restart Lisa's Host") {
                        Task { await session.restartHost() }
                    }
                    .help("Stops the host as lisa serve does, then starts it again.")
                }
                if session.host.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(session.host.isWorking)
            InlineLoadState(
                state: settings.health, emptyMessage: "", isEmpty: { _ in false },
                retry: { await settings.refreshHealth() },
                content: { _ in runtimeState })
        }
    }

    private var mode: HostMode { session.host.mode }

    @ViewBuilder
    private var runtimeState: some View {
        if let runtime = settings.runtime {
            LabeledContent("Status") {
                Label(runtime.message, systemImage: runtime.needsAttention ? "exclamationmark.triangle" : "checkmark")
            }
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("Running for", value: runtime.uptimePhrase(at: context.date))
                    Text(runtime.lastCyclePhrase(at: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let problem = runtime.lastCycleProblem {
                Label(problem, systemImage: "exclamationmark.octagon")
                    .foregroundStyle(.red)
            }
            ForEach(runtime.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
            }
            LabeledContent("Deliveries", value: runtime.outboxMessage)
        }
    }
}
