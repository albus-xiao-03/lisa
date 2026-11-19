// Paired devices on Settings and Health: each device and whether it can receive notifications, removing one, and
// creating a one-time pairing code for a new iPhone or iPad, shown until it expires.

import Foundation
import LisaAPIContract
import LisaPresentation
import SwiftUI

/// The paired devices and pairing (UI-01: paired devices; plan §6.3). This Mac's own local-notification installation
/// is listed too, as "This Mac"; it is managed under This Mac, not removed here. A pairing code is created by the owner
/// on the host, which this app is or connects to; it lasts 10 minutes and only until the host restarts.
struct PairedDevicesSection: View {
    let devices: PairedDevicesModel
    let host: EmbeddedHostController
    /// The host's identifier of this Mac's local-notification installation, when known.
    let thisMacDeviceID: String?
    /// Asks the owner to confirm removing a device.
    let remove: (PairedDeviceSummary) -> Void

    var body: some View {
        Section("Paired Devices") {
            InlineLoadState(
                state: devices.state, emptyMessage: PairedDevicesModel.emptyMessage, isEmpty: { $0.isEmpty },
                retry: { await devices.load() },
                content: { _ in
                    ForEach(devices.summaries) { device in
                        row(device)
                    }
                })
            pairing
            if let outcome = devices.lastOutcome {
                ActionOutcomeLabel(outcome: outcome)
            }
        }
    }

    private func row(_ device: PairedDeviceSummary) -> some View {
        let isThisMac = device.id == thisMacDeviceID
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isThisMac ? "\(device.name) (This Mac)" : device.name)
                Text("\(device.kindLabel) · \(device.notificationStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimelineView(.everyMinute) { context in
                    Text(device.lastSeenPhrase(at: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(device.accessibilityLabel)
            Spacer(minLength: 0)
            if devices.removingDeviceIDs.contains(device.id) {
                ProgressView()
                    .controlSize(.small)
            } else if device.isActive, !isThisMac {
                Button("Remove…", role: .destructive) { remove(device) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var pairing: some View {
        if let code = devices.pairingCode {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pairing code")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(code.code)
                    .font(.system(.largeTitle, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code \(code.code.map(String.init).joined(separator: " "))")
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(devices.pairingCodeExpiry(at: context.date) ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "In Lisa on your iPhone or iPad, open Connection, enter this host's address and certificate, then "
                        + "this code."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Hide Code") { devices.hidePairingCode() }
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
        } else {
            HStack {
                Button("Create Pairing Code") {
                    Task { await devices.createPairingCode() }
                }
                .disabled(devices.isCreatingCode || !canPair)
                if devices.isCreatingCode {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        if let note = pairingNote {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Whether the host serves the API that devices pair through.
    private var canPair: Bool {
        switch host.mode {
        case .embedded(_, let problem): problem == nil
        case .client: true
        case .starting, .unavailable: false
        }
    }

    /// Where devices reach the host, or why they can't pair now.
    private var pairingNote: String? {
        switch host.mode {
        case .embedded(let listener, let problem):
            problem == nil
                ? "Devices reach this host at \(listener)."
                : "Devices can't pair while the host's network API isn't running."
        case .client: "Devices pair with lisa serve, at the address in your configuration."
        case .starting, .unavailable: nil
        }
    }
}
