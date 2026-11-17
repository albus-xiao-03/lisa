// This device's notification settings (UI-02, NOTIFY-05, NOTIFY-06): the system permission and what the host knows of
// it, and the preferences the host keeps for this device, changed through the durable queue.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI
import UIKit

/// This device's notification settings.
///
/// - Permission: read at launch and on each return to the foreground and reported to the host, which sends nothing
///   while notifications are off. Lisa asks for permission only when pairing offers it (plan §6.5), so a device that
///   has not been asked is pointed to the connection screen; a denial can only be changed in Settings.
/// - Preferences: on the host. A change expects the version shown and waits in the queue while the host can't be
///   reached; a newer version on the host is a conflict the owner resolves.
struct NotificationSettingsView: View {
    let model: NotificationSettingsModel
    @Environment(CompanionNavigation.self) private var navigation

    var body: some View {
        Form {
            permissionSection
            preferencesSections
            if let conflict = model.conflict {
                Section("Your Change Wasn't Applied") {
                    ConflictNotice(
                        message: conflict.message, canApplyAgain: conflict.entryID != nil,
                        applyAgain: { await model.applyAgain() }, discard: { await model.discardConflict() })
                }
            }
            if let outcome = model.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
        }
        .navigationTitle("Notifications")
        .refreshable { [model] in
            await model.reportPermission()
            await model.load()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        await model.reportPermission()
                        await model.load()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        Section(
            content: {
                LabeledContent("On This Device", value: permissionText)
                if model.permission?.authorization == .denied,
                    let settings = URL(string: UIApplication.openNotificationSettingsURLString)
                {
                    Link("Open Settings", destination: settings)
                }
                if model.permission?.authorization == .notDetermined {
                    Button("Open Connection", systemImage: "link") { navigation.show(.connection) }
                }
                if let registration = model.registration {
                    Label(
                        registration.canReceiveNotifications
                            ? "Your Lisa host can notify this device." : "Your Lisa host isn't notifying this device.",
                        systemImage: registration.canReceiveNotifications ? "checkmark.circle" : "bell.slash")
                }
                if model.reportPending {
                    Button("Tell Your Host Again", systemImage: "arrow.clockwise") {
                        Task { await model.reportPermission() }
                    }
                }
            },
            header: { Text("Permission") },
            footer: { Text(permissionFooter) })
    }

    private var permissionText: String {
        switch model.permission?.authorization {
        case .authorized?: "Allowed"
        case .provisional?: "Allowed quietly"
        case .ephemeral?: "Allowed for now"
        case .denied?: "Off"
        case .notDetermined?: "Not set up"
        case .unknown?: "Unknown"
        case nil: "Checking…"
        }
    }

    private var permissionFooter: String {
        switch model.permission?.authorization {
        case .denied?:
            "Notifications from Lisa are off in Settings, so your host doesn't send them. Turn them on in Settings."
        case .notDetermined?:
            "Lisa offers to turn notifications on when you pair this device, in Connection."
        default:
            "Your system settings, Focus and lock-screen previews always decide what appears."
        }
    }

    // MARK: - Preferences

    @ViewBuilder
    private var preferencesSections: some View {
        if let shown = model.displayed {
            Section(
                content: {
                    Toggle(
                        "Notifications from Lisa",
                        isOn: binding(shown.enabled) { [model] isOn in await model.setEnabled(isOn) }
                    )
                    .disabled(model.isUpdating)
                    if model.pendingChange != nil {
                        SyncBadge(kind: .waiting)
                    }
                    if model.preferences.isStale, let fetchedAt = model.preferences.result?.fetchedAt {
                        AgeText(prefix: "Not updated; last read", date: fetchedAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.isUpdating {
                        ProgressView()
                    }
                },
                header: { Text("From Your Lisa Host") })
            Section("Notify Me About") {
                ForEach(NotificationCategoryID.allCases, id: \.self) { category in
                    Toggle(
                        Self.title(of: category),
                        isOn: binding(model.isEnabled(category)) { [model] isOn in
                            await model.setCategory(category, enabled: isOn)
                        })
                }
            }
            .disabled(!shown.enabled || model.isUpdating)
            Section(
                content: {
                    Toggle(
                        "Show Titles",
                        isOn: binding(shown.showTitles) { [model] isOn in await model.setShowTitles(isOn) })
                    Toggle(
                        "Time Sensitive for Urgent Deadlines",
                        isOn: binding(shown.allowTimeSensitive) { [model] isOn in
                            await model.setAllowTimeSensitive(isOn)
                        })
                },
                header: { Text("Privacy and Urgency") },
                footer: {
                    Text(
                        "Show Titles adds a shortened title; notifications never include descriptions, email content or "
                            + "addresses. Time Sensitive is used only for a high-priority confirmed deadline within 15 "
                            + "minutes whose task is still open, and Focus and quiet hours still apply.")
                }
            )
            .disabled(model.isUpdating)
        } else if let failure = model.preferences.failure {
            Section("From Your Lisa Host") {
                Text(failure.message)
                Button("Try Again") {
                    Task { await model.load() }
                }
            }
        } else {
            Section("From Your Lisa Host") {
                ProgressView()
            }
        }
    }

    /// A toggle's binding: it shows `value`, and a change runs `change`, which queues it.
    private func binding(
        _ value: Bool, _ change: @escaping @MainActor @Sendable (Bool) async -> Void
    ) -> Binding<Bool> {
        Binding(get: { value }, set: { isOn in Task { @MainActor in await change(isOn) } })
    }

    private static func title(of category: NotificationCategoryID) -> String {
        switch category {
        case .reminder: "Reminders"
        case .overdue: "Past-Due Tasks"
        case .planBlock: "Planned Blocks"
        case .eventProposal: "Events to Review"
        case .commitmentChange: "Commitment Changes"
        case .brief: "Your Daily Brief"
        }
    }
}
