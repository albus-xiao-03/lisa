// The pending-actions screen (UI-02, UI-03, NOTIFY-05): what waits for the host, what the host refused because the
// item changed, and what did not go through, from the app, Siri or a notification.

import LisaClient
import LisaPresentation
import SwiftUI

/// The offline queue. Waiting actions are sent in order with their original request IDs, so the host applies each one
/// once; they are sent when the app becomes active and when the owner chooses Send Now (Command-R). Nothing polls
/// the host. A conflict is applied again to the current version only when the owner chooses; notification receipts
/// are the app's own bookkeeping and are listed only in Diagnostics.
struct PendingActionsView: View {
    let model: PendingActionsModel
    /// Reads the other screens again after the queue changed here.
    let onQueueChanged: @MainActor () async -> Void
    @State private var lastOutcome: ActionOutcome?
    @State private var discarding: PendingAction?
    @State private var isConfirmingDiscard = false

    var body: some View {
        List {
            statusSection
            if !model.conflicts.isEmpty {
                Section("Changed on Your Host") {
                    ForEach(model.conflicts) { action in
                        decisionRow(action)
                    }
                }
            }
            if !model.failures.isEmpty {
                Section("Didn't Go Through") {
                    ForEach(model.failures) { action in
                        decisionRow(action)
                    }
                }
            }
            if !waiting.isEmpty {
                Section("Waiting for Your Host") {
                    ForEach(waiting) { action in
                        PendingActionRow(action: action)
                            .swipeActions {
                                Button("Discard", systemImage: "trash") {
                                    discarding = action
                                    isConfirmingDiscard = true
                                }
                                .tint(Color.red)
                            }
                    }
                }
            }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    "Nothing Waiting", systemImage: "checkmark.circle",
                    description: Text("Everything you did has reached your Lisa host."))
            }
        }
        .navigationTitle("Pending Actions")
        .refreshable { [model] in await model.reload() }
        .task { [model] in await model.reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Send Now", systemImage: "paperplane") {
                    Task { await send() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isFlushing)
            }
        }
        .confirmationDialog(
            "Discard This Action?", isPresented: $isConfirmingDiscard, titleVisibility: .visible,
            presenting: discarding,
            actions: { action in
                Button("Discard", role: .destructive) {
                    Task { await discard(action) }
                }
            },
            message: { action in
                Text(
                    action.attempts > 0
                        ? "It may already have reached your host; discarding it here doesn't undo it there."
                        : "It won't be sent to your Lisa host.")
            })
    }

    /// The owner's own actions that wait for the host.
    private var waiting: [PendingAction] {
        model.pending.filter(\.isOwnerAction)
    }

    private var isEmpty: Bool {
        waiting.isEmpty && model.conflicts.isEmpty && model.failures.isEmpty
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isFlushing || lastOutcome != nil || model.lastFlush != nil {
            Section {
                if model.isFlushing {
                    ProgressView("Sending…")
                }
                if let lastOutcome {
                    ActionOutcomeLabel(outcome: lastOutcome)
                }
                if let report = model.lastFlush, let sentAt = model.lastFlushAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.summary(of: report))
                        AgeText(prefix: "Last sent", date: sentAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func decisionRow(_ action: PendingAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PendingActionRow(action: action)
            if action.status == .conflict {
                ConflictNotice(
                    message: "Review the item, then apply your change again or discard it.",
                    canApplyAgain: action.currentRevision != nil, applyAgain: { await resubmit(action) },
                    discard: { await discard(action) })
            } else {
                HStack {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await resubmit(action) }
                    }
                    Button(
                        role: .destructive, action: { Task { await discard(action) } },
                        label: { Label("Discard", systemImage: "trash") })
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func send() async {
        await model.flush()
        await onQueueChanged()
    }

    private func resubmit(_ action: PendingAction) async {
        lastOutcome = await model.resubmit(action.id)
        await onQueueChanged()
    }

    private func discard(_ action: PendingAction) async {
        await model.discard(action.id)
        await onQueueChanged()
    }

    /// What the last sending did, in counts.
    private static func summary(of report: FlushReport) -> String {
        var parts: [String] = []
        if !report.applied.isEmpty { parts.append("\(report.applied.count) sent") }
        if !report.conflicts.isEmpty { parts.append("\(report.conflicts.count) changed on your host") }
        if !report.failed.isEmpty { parts.append("\(report.failed.count) didn't go through") }
        if report.remaining > 0 { parts.append("\(report.remaining) still waiting") }
        return parts.isEmpty ? "Nothing needed sending." : parts.joined(separator: ", ") + "."
    }
}
