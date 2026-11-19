// Keychain secrets on Settings and Health: each `keychain:` reference in the configuration, whether this Mac's
// Keychain holds it, setting, replacing or removing it, and restarting the host so it reads them again.

import Foundation
import LisaSecrets
import SwiftUI

/// The configuration's `keychain:` secrets (SEC-01, D-48). Values are never shown, only whether each is stored.
struct KeychainSecretsSection: View {
    let secrets: KeychainSecretsModel
    let session: MacSession
    /// Opens the sheet that sets the secret with this identifier.
    let edit: (String) -> Void

    var body: some View {
        Section("Secrets in Keychain") {
            if secrets.entries.isEmpty {
                Text("Lisa's configuration refers to no keychain: secrets.")
                    .foregroundStyle(.secondary)
            }
            ForEach(secrets.entries) { entry in
                row(entry)
            }
            if session.host.mode.isClient {
                Text("lisa serve can't read keychain: secrets; they apply only while Lisa runs its host in this app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if secrets.changedSinceStart {
                restartNote
            }
            if let problem = secrets.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func row(_ entry: KeychainSecretsModel.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.reference.description)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("Used by \(entry.settings.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(stateText(entry.state), systemImage: entry.state == .stored ? "checkmark.seal" : "key")
                    .font(.caption)
                    .foregroundStyle(entry.state == .stored ? Color.secondary : Color.orange)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(entry.state == .stored ? "Replace…" : "Set…") { edit(entry.id) }
                .controlSize(.small)
            if entry.state == .stored {
                Button("Remove", role: .destructive) { secrets.remove(entry.reference) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var restartNote: some View {
        HStack {
            Text("Lisa's host reads secrets when it starts.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if session.host.mode.isEmbedded {
                Button("Restart Lisa's Host") {
                    Task { await session.restartHost() }
                }
                .disabled(session.host.isWorking)
            } else if session.host.mode.canRetry {
                Button("Try Again") {
                    Task { await session.retryHost() }
                }
                .disabled(session.host.isWorking)
            }
        }
    }

    private func stateText(_ state: KeychainSecretsModel.Entry.State) -> String {
        switch state {
        case .stored: "Stored in this Mac's Keychain"
        case .missing: "Not stored yet"
        case .unreadable(let reason): "Can't be read: \(reason)"
        }
    }
}
