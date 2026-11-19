// Settings and Health (UI-01): Lisa's host and its runtime state, the sources, delivery modes and preferences, the
// model configuration, paired devices with pairing codes, this Mac's notifications and login item, Keychain secrets,
// and the way to diagnostics.

import Foundation
import LisaPresentation
import SwiftUI

/// The settings and health screen (UI-01: sources, delivery policy, model configuration, runtime state, paired devices
/// and notification status). Health is read when the screen asks; nothing polls the host, and while the host can't be
/// reached the screen keeps what it last read, marked as not current. Settings that come only from the configuration
/// file are shown as the host reports them and changed in that file. Command-R reads everything again.
struct SettingsHealthView: View {
    let session: MacSession
    let models: MacModels

    @State private var editingPreferenceKey: String?
    @State private var editingSecretID: String?
    @State private var removingDevice: PairedDeviceSummary?

    var body: some View {
        Form {
            HostSection(session: session, settings: models.settings)
            SourcesSection(settings: models.settings)
            DeliverySection(
                settings: models.settings, preferences: models.memory, edit: { editingPreferenceKey = $0 })
            ModelSection(settings: models.settings)
            PairedDevicesSection(
                devices: models.settings.devices, host: session.host,
                thisMacDeviceID: session.notifications.installation?.deviceID, remove: { removingDevice = $0 })
            ThisMacSection(
                notifications: session.notifications, loginItem: session.loginItem, host: session.host,
                warnings: models.settings.notificationWarnings)
            KeychainSecretsSection(secrets: session.secrets, session: session, edit: { editingSecretID = $0 })
            Section(
                content: {
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(session: session, models: models)
                    }
                },
                footer: {
                    Text("Identifiers, versions, readiness checks and the offline queue, for troubleshooting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                })
        }
        .formStyle(.grouped)
        .navigationTitle("Settings and Health")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(models.settings.health.isLoading)
            }
        }
        .sheet(isPresented: isShowing($editingPreferenceKey)) {
            if let editingPreferenceKey {
                PreferenceEditSheet(model: models.memory, key: editingPreferenceKey)
            }
        }
        .sheet(isPresented: isShowing($editingSecretID)) {
            if let entry = session.secrets.entries.first(where: { $0.id == editingSecretID }) {
                KeychainSecretSheet(secrets: session.secrets, entry: entry)
            }
        }
        .confirmationDialog(
            "Remove “\(removingDevice?.name ?? "this device")” from Lisa?", isPresented: isShowing($removingDevice),
            presenting: removingDevice,
            actions: { device in
                Button("Remove", role: .destructive) {
                    Task { await remove(device) }
                }
            },
            message: { _ in
                Text(
                    "Its credential stops working at once and it gets no more notifications. It can pair again with "
                        + "a new code.")
            }
        )
        .task {
            if case .idle = models.settings.health { await refresh() }
        }
    }

    private func refresh() async {
        session.loginItem.refresh()
        session.secrets.load(session.host.configuration?.configuration)
        await session.notifications.refresh(force: true)
        await models.settings.load()
    }

    private func remove(_ device: PairedDeviceSummary) async {
        let paired = models.settings.devices
        guard let shown = paired.devices.first(where: { $0.id == device.id }) else { return }
        await paired.remove(shown)
    }

    /// Whether `value` is set, as a sheet or dialog shows it; dismissing clears it.
    private func isShowing<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { shown in if !shown { value.wrappedValue = nil } })
    }
}
