// The connectivity screen (UI-02, NOTIFY-07): whether the host can be reached, when it last answered, how old the data
// saved on this device is, and what waits to sync.

import LisaClient
import LisaPresentation
import SwiftUI

/// Connectivity and cached-data age. The status follows the app's latest exchange with the host; Check Now
/// (Command-R) asks the host directly. Nothing checks in the background.
struct ConnectivityView: View {
    let model: ConnectivityModel
    let pendingActions: PendingActionsModel
    @Environment(CompanionNavigation.self) private var navigation

    var body: some View {
        List {
            Section {
                Label(model.status.message, systemImage: symbol)
                if let reached = model.lastSuccessfulContact {
                    AgeText(prefix: "Last reached", date: reached)
                        .foregroundStyle(.secondary)
                }
                if model.isChecking {
                    ProgressView("Checking…")
                }
            }
            Section(
                content: {
                    if model.cachedData.isEmpty {
                        Text("Nothing is saved on this device yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.cachedData, id: \.self) { saved in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(of: saved))
                            AgeText(prefix: "Saved", date: saved.fetchedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                },
                header: { Text("Saved on This Device") },
                footer: {
                    Text(
                        "While your Lisa host can't be reached, Lisa shows these saved copies with their age, and "
                            + "keeps what you do until it can be sent.")
                })
            Section("Waiting to Sync") {
                Button(action: { navigation.show(.pending) }, label: { pendingSummary })
            }
        }
        .navigationTitle("Connectivity")
        .task { [model] in await model.refreshCachedData() }
        .refreshable { [model] in await model.check() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Check Now", systemImage: "arrow.clockwise") {
                    Task { await model.check() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isChecking)
            }
        }
    }

    private var pendingSummary: some View {
        let waiting = pendingActions.pendingCount
        let decisions = pendingActions.attentionCount
        let title: String = waiting == 1 ? "1 action waits for your host" : "\(waiting) actions wait for your host"
        let value: String = decisions == 0 ? "" : "\(decisions) need you"
        return LabeledContent(title, value: value)
    }

    private var symbol: String {
        switch model.status {
        case .unknown: "questionmark.circle"
        case .reachable: "checkmark.circle"
        case .unreachable: "wifi.exclamationmark"
        case .incompatible: "arrow.triangle.2.circlepath"
        case .notPaired: "link.badge.plus"
        case .revoked: "person.crop.circle.badge.xmark"
        }
    }

    private static func title(of saved: CachedDataSummary) -> String {
        let what =
            switch saved.kind {
            case .brief: "Brief"
            case .rundown: "Rundown"
            case .tasks: "Task list"
            }
        guard let date = saved.localDate else { return what }
        return "\(what) for \(LocalDayText.words(for: date, style: .abbreviated))"
    }
}
