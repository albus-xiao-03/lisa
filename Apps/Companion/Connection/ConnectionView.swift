// The connection screen (UI-02, plan §6.3, NOTIFY-07): the Lisa host's address and certificate, pairing with a
// one-time code, and unpairing or forgetting the pairing.

import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Connection and device credentials. The device credential that pairing returns goes straight to Keychain and is
/// never shown. Pairing offers to turn notifications on; that offer is the only place Lisa asks for notification
/// permission (plan §6.5). Unpairing asks the host to remove this device and clears what this device saved; Forget
/// drops the pairing here only, for a host that is gone.
struct ConnectionView: View {
    @Bindable var connection: ConnectionModel
    let hostConnection: HostConnectionController
    let notificationSettings: NotificationSettingsModel
    /// What the session does after pairing: APNs registration and reading every screen again.
    let onPaired: @MainActor () async -> Void
    @State private var usesOwnCertificate = false
    @State private var offersNotifications = false
    @State private var confirmsUnpair = false
    @State private var confirmsForget = false

    var body: some View {
        Form {
            addressSection
            Section {
                NavigationLink(destination: HostTrustView(controller: hostConnection)) {
                    LabeledContent("Certificate", value: usesOwnCertificate ? "Your certificate" : "System trust")
                }
            }
            pairingSection
            if let outcome = connection.lastOutcome {
                Section {
                    ActionOutcomeLabel(outcome: outcome)
                }
            }
        }
        .navigationTitle("Connection")
        .onAppear { usesOwnCertificate = hostConnection.trust != nil }
        .task { [connection] in await connection.refresh() }
        .refreshable { [connection] in
            await connection.refresh()
            await connection.refreshDevice()
        }
        .alert(
            "Turn On Notifications?", isPresented: $offersNotifications,
            actions: {
                Button("Turn On") {
                    Task {
                        await notificationSettings.requestAuthorization()
                        await connection.refreshDevice()
                    }
                }
                Button("Not Now", role: .cancel) {}
            },
            message: {
                Text(
                    "Lisa can notify this device about reminders, deadlines and your brief. Notifications show only "
                        + "generic text unless you choose to show titles.")
            }
        )
        .confirmationDialog(
            "Unpair This Device?", isPresented: $confirmsUnpair, titleVisibility: .visible,
            actions: {
                Button("Unpair and Keep Waiting Actions") {
                    Task { await connection.unpair() }
                }
                Button("Unpair and Discard Waiting Actions", role: .destructive) {
                    Task { await connection.unpair(discardingQueuedActions: true) }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text(
                    "Your host removes this device. This device clears its saved brief, rundown and tasks and its "
                        + "delivered notifications. Waiting actions can be kept and sent after you pair again.")
            }
        )
        .confirmationDialog(
            "Forget the Pairing on This Device?", isPresented: $confirmsForget, titleVisibility: .visible,
            actions: {
                Button("Forget and Keep Waiting Actions") {
                    Task { await connection.forgetPairing() }
                }
                Button("Forget and Discard Waiting Actions", role: .destructive) {
                    Task { await connection.forgetPairing(discardingQueuedActions: true) }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text(
                    "Use this when your Lisa host is gone for good. Your host still lists this device until you "
                        + "remove it there.")
            })
    }

    // MARK: - Address

    private var addressSection: some View {
        Section(
            content: {
                TextField("https://lisa.example.net", text: $connection.addressText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveAddress)
                if let issue = connection.addressIssue {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                Button("Save Address", systemImage: "checkmark", action: saveAddress)
                    .disabled(connection.addressText.isEmpty)
                if let endpoint = connection.endpoint {
                    LabeledContent("Requests go to", value: endpoint.description)
                }
            },
            header: { Text("Lisa Host") },
            footer: {
                Text(
                    "Your Lisa host's HTTPS address, on your network or over your VPN. Lisa uses no relay or cloud "
                        + "service.")
            })
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingSection: some View {
        switch connection.state {
        case .unknown:
            Section("Pairing") {
                ProgressView()
            }
        case .notPaired, .revoked:
            Section(
                content: {
                    if connection.state == .revoked {
                        Label(
                            "Your Lisa host removed this device. Pair it again with a new code.",
                            systemImage: "person.crop.circle.badge.xmark")
                    }
                    TextField("Pairing code", text: $connection.pairingCode)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(pair)
                    Button("Pair This Device", systemImage: "link.badge.plus", action: pair)
                        .disabled(connection.isWorking || connection.endpoint == nil)
                    if connection.isWorking {
                        ProgressView()
                    }
                },
                header: { Text("Pairing") },
                footer: {
                    Text(
                        "Create a pairing code on your Lisa host and enter it here. The device credential stays in "
                            + "this device's Keychain and is never shown.")
                })
        case .paired:
            Section(
                content: {
                    if let device = connection.device {
                        LabeledContent("Paired as", value: device.name)
                        LabeledContent("Since", value: device.pairedAt.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Label("Paired with your Lisa host", systemImage: "checkmark.seal")
                    }
                    if notificationSettings.permission?.authorization == .notDetermined {
                        Button("Turn On Notifications", systemImage: "bell.badge") {
                            offersNotifications = true
                        }
                    }
                    Button(
                        role: .destructive, action: { confirmsUnpair = true },
                        label: { Label("Unpair This Device", systemImage: "link") }
                    )
                    .disabled(connection.isWorking)
                    Button(
                        action: { confirmsForget = true },
                        label: { Label("Forget the Pairing on This Device", systemImage: "trash") }
                    )
                    .disabled(connection.isWorking)
                    if connection.isWorking {
                        ProgressView()
                    }
                },
                header: { Text("Pairing") },
                footer: {
                    Text(
                        "Unpairing asks your host to remove this device and clears what this device saved. Forget is "
                            + "for a host that is gone for good.")
                })
        }
    }

    private func saveAddress() {
        connection.saveAddress()
    }

    private func pair() {
        Task {
            let outcome = await connection.pair()
            guard outcome.isDone else { return }
            await onPaired()
            if notificationSettings.permission?.authorization == .notDetermined {
                offersNotifications = true
            }
        }
    }
}
