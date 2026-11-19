// This Mac on Settings and Health: whether Lisa's notifications are allowed here and reach this Mac, turning them on
// when the owner chooses, the host's notes about devices that can't receive notifications, and starting at login.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// This Mac's notification status (UI-01, NOTIFY-05) and the login item. Permission is requested only when the owner
/// chooses Turn On Notifications.
struct ThisMacSection: View {
    let notifications: MacNotificationsModel
    let loginItem: LoginItemController
    let host: EmbeddedHostController
    /// The host's explanations of devices that can't receive notifications.
    let warnings: [String]

    var body: some View {
        Section("This Mac") {
            LabeledContent("Notifications", value: permissionText)
            if host.mode.isEmbedded {
                embeddedStatus
            } else if host.mode.isClient {
                Text(MacNotificationsModel.clientModeNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let problem = notifications.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "bell.slash")
                    .font(.callout)
            }
            Toggle("Open Lisa when you log in", isOn: opensAtLogin)
            Text(loginItem.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
            if loginItem.needsApproval {
                Button("Open Login Items Settings") { loginItem.openLoginItemsSettings() }
            }
            if let problem = loginItem.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var embeddedStatus: some View {
        if notifications.canRequestPermission {
            Button("Turn On Notifications…") {
                Task { await notifications.requestPermission() }
            }
            .disabled(notifications.isRequesting)
            .help("macOS asks whether Lisa may show alerts and play sounds.")
        } else if notifications.permission?.authorization == .denied {
            Text("Notifications for Lisa are off. Turn them on in System Settings → Notifications → Lisa.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let installation = notifications.installation {
            if installation.isActive {
                Text(
                    installation.canReceiveNotifications
                        ? "Lisa's host posts its notifications on this Mac when they are due."
                        : "Lisa's host doesn't post notifications on this Mac until they are allowed."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Text("This Mac was removed from Lisa's devices, so it gets no notifications.")
                    .font(.callout)
                Button("Get Notifications on This Mac Again") {
                    Task { await notifications.registerAgain() }
                }
            }
        }
    }

    private var permissionText: String {
        switch notifications.permission?.authorization {
        case nil: "Not read yet"
        case .authorized?: "Allowed"
        case .denied?: "Not allowed"
        case .notDetermined?: "Not asked yet"
        case .provisional?: "Delivered quietly"
        case .ephemeral?: "Allowed for now"
        case .unknown?: "Unknown"
        }
    }

    private var opensAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem.isRequested },
            set: { opens in loginItem.setOpensAtLogin(opens) })
    }
}
