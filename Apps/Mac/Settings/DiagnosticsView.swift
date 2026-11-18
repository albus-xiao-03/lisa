// Diagnostics (UI-01): the implementation details the daily screens leave out — paths, identifiers, versions, the
// host's readiness checks, recovery notes, this Mac's notification record, and the offline queue — for troubleshooting.
// It never shows a credential, a secret or a push token.

import Foundation
import LisaClient
import LisaHost
import LisaPresentation
import SwiftUI

/// Implementation details, kept out of the daily flow (UI-01: internal details belong in diagnostics). Everything here
/// is read-only and can be selected and copied. The readiness checks are those of `lisa doctor`; they contact no
/// service and send nothing.
struct DiagnosticsView: View {
    let session: MacSession
    let models: MacModels

    @State private var checks: [HostDiagnostic]?
    @State private var isChecking = false

    var body: some View {
        Form {
            appSection
            hostSection
            checksSection
            thisMacSection
            connectionSection
            queueSection
            savedDataSection
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .navigationTitle("Diagnostics")
        .task {
            await models.pendingActions.reload()
            await models.connectivity.refreshCachedData()
        }
    }

    // MARK: - Sections

    private var appSection: some View {
        Section("App") {
            LabeledContent("Bundle identifier", value: ThisAppBuild.bundleIdentifier ?? "none")
            LabeledContent("Version", value: MacHostConfiguration.applicationVersion)
            LabeledContent("Push environment of this build", value: ThisAppBuild.apnsEnvironment.rawValue)
            LabeledContent("Installation", value: session.credentials.installationID)
            if let problem = session.environment.setupProblem {
                LabeledContent("Setup problem", value: problem)
            }
            if let problem = session.host.keychainProblem {
                LabeledContent("Keychain", value: problem)
            }
        }
    }

    private var hostSection: some View {
        let host = session.host
        return Section("Host") {
            LabeledContent("Mode", value: host.mode.title)
            LabeledContent("Configuration file", value: host.configuration?.path ?? MacHostConfiguration.resolvedPath)
            if let settings = host.configuration?.settings {
                LabeledContent("Data directory", value: settings.dataDirectory.path(percentEncoded: false))
            }
            if let port = host.ownerListenerPort {
                LabeledContent("Owner listener", value: "127.0.0.1:\(port)")
            }
            if let runtime = models.settings.runtime {
                LabeledContent("Host version", value: runtime.applicationVersion)
                LabeledContent("API version", value: runtime.apiVersion)
                LabeledContent("Store schema", value: "\(runtime.schemaVersion)")
            }
            ForEach(host.recoveryNotes, id: \.self) { note in
                LabeledContent("Recovery", value: note)
            }
            ForEach(host.unavailableCapabilities, id: \.self) { note in
                LabeledContent("Unavailable", value: note)
            }
        }
    }

    private var checksSection: some View {
        Section("Readiness Checks") {
            HStack {
                Button("Run Checks") {
                    Task { await runChecks() }
                }
                .disabled(isChecking || session.host.configuration == nil)
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ForEach(checks ?? [], id: \.self) { check in
                Label(
                    title: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    },
                    icon: {
                        Image(systemName: check.ok ? "checkmark.circle" : "xmark.octagon")
                            .foregroundStyle(check.ok ? Color.green : Color.red)
                    }
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var thisMacSection: some View {
        let notifications = session.notifications
        return Section("This Mac's Notifications") {
            if let installation = notifications.installation {
                LabeledContent("Installation on the host", value: installation.deviceID)
                LabeledContent("Registered", value: installation.isActive ? "yes" : "removed")
                LabeledContent("Permission the host has", value: installation.reportedAuthorization)
                LabeledContent("Host sends here", value: installation.canReceiveNotifications ? "yes" : "no")
            }
            LabeledContent("Reported", value: Self.text(notifications.lastReportedAt))
            LabeledContent(
                "System permission", value: notifications.permission?.authorization.rawValue ?? "not read")
            ForEach(Self.lines(of: notifications.permission?.settings ?? [:]), id: \.self) { line in
                Text(verbatim: line)
                    .font(.footnote.monospaced())
            }
        }
    }

    private var connectionSection: some View {
        let connectivity = models.connectivity
        return Section("Connection") {
            LabeledContent("Status", value: connectivity.status.message)
            LabeledContent("Last reached", value: Self.text(connectivity.lastSuccessfulContact))
            LabeledContent("Last attempt", value: Self.text(connectivity.lastAttempt))
        }
    }

    private var queueSection: some View {
        let queue = models.pendingActions
        let entries = queue.pending + queue.conflicts + queue.failures
        return Section("Offline Queue") {
            LabeledContent(
                "Entries",
                value:
                    "\(queue.pending.count) waiting, \(queue.conflicts.count) conflicts, \(queue.failures.count) failed"
            )
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summary)
                    Text(verbatim: Self.details(of: entry))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if let report = queue.lastFlush {
                Text(verbatim: Self.details(of: report, at: queue.lastFlushAt))
                    .font(.caption.monospaced())
            }
            Button("Send Now") {
                Task { await queue.flush() }
            }
            .disabled(queue.isFlushing || queue.pending.isEmpty)
        }
    }

    private var savedDataSection: some View {
        Section("Saved on This Mac") {
            ForEach(models.connectivity.cachedData, id: \.self) { saved in
                LabeledContent(
                    saved.kind.rawValue, value: "\(saved.localDate ?? "latest"), saved \(Self.text(saved.fetchedAt))")
            }
            if let result = models.rundown.state.result {
                Text(verbatim: "rundown \(result.value.planID) r\(result.value.revision), \(result.source)")
                    .font(.caption.monospaced())
            }
            if let result = models.brief.state.result {
                Text(
                    verbatim: "brief \(result.value.briefID) r\(result.value.revision) v\(result.value.version) "
                        + "\(result.value.state), \(result.source)"
                )
                .font(.caption.monospaced())
            }
        }
    }

    // MARK: - Actions and text

    private func runChecks() async {
        isChecking = true
        defer { isChecking = false }
        checks = await session.host.readinessChecks()
    }

    private static func text(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "never"
    }

    private static func lines(of settings: [String: String]) -> [String] {
        settings.keys.sorted().map { "\($0) = \(settings[$0] ?? "")" }
    }

    private static func details(of entry: PendingAction) -> String {
        var parts = [
            entry.kind.rawValue, entry.status.rawValue, "request \(entry.requestID)", "attempts \(entry.attempts)",
        ]
        if let last = entry.lastAttemptAt { parts.append("last \(text(last))") }
        if let next = entry.nextAttemptAt { parts.append("next \(text(next))") }
        if let revision = entry.currentRevision { parts.append("host revision \(revision)") }
        if entry.mayHaveBeenApplied { parts.append("may have been applied") }
        if let message = entry.message { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    private static func details(of report: FlushReport, at date: Date?) -> String {
        "last flush \(text(date)): applied \(report.applied.count), conflicts \(report.conflicts.count), failed "
            + "\(report.failed.count), remaining \(report.remaining), stop \(String(describing: report.stop))"
    }
}
