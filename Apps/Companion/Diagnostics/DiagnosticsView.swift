// The diagnostics screen: the implementation details the daily screens leave out — identifiers, revisions, request
// IDs, raw states and settings — for troubleshooting. It never shows the device credential or the push token.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import SwiftUI

/// Implementation details, kept out of the daily flow (UI-02: calm presentation). Everything here is read-only and
/// can be selected and copied.
struct DiagnosticsView: View {
    let session: CompanionSession
    let models: CompanionModels

    var body: some View {
        List {
            appSection
            connectionSection
            pairingSection
            notificationsSection
            queueSection
            dataSection
        }
        .navigationTitle("Diagnostics")
        .textSelection(.enabled)
        .task { [models] in
            await models.pendingActions.reload()
            await models.connection.refresh()
        }
        .refreshable { [models] in
            await models.pendingActions.reload()
            await models.connectivity.refreshCachedData()
        }
    }

    // MARK: - Sections

    private var appSection: some View {
        Section("App") {
            LabeledContent("Bundle identifier", value: ThisAppBuild.bundleIdentifier ?? "none")
            LabeledContent("Push environment", value: ThisAppBuild.apnsEnvironment.rawValue)
            if let problem = session.environment.setupProblem {
                LabeledContent("Setup problem", value: problem)
            }
            if let problem = models.hostConnection.loadProblem {
                LabeledContent("Connection settings", value: problem)
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Host address", value: models.connection.endpoint?.description ?? "not set")
            LabeledContent("Trust", value: trustText)
            LabeledContent("Status", value: String(describing: models.connectivity.status))
            LabeledContent("Last reached", value: Self.text(models.connectivity.lastSuccessfulContact))
            LabeledContent("Last attempt", value: Self.text(models.connectivity.lastAttempt))
        }
    }

    private var pairingSection: some View {
        Section("Pairing") {
            LabeledContent("Installation", value: models.connection.installationID ?? "unknown")
            LabeledContent("Pairing", value: String(describing: models.connection.state))
            if let device = models.connection.device {
                LabeledContent("Device", value: device.id)
                LabeledContent("Device state", value: device.state)
                LabeledContent("Transport", value: device.transport)
                LabeledContent("Host's permission record", value: device.authorization.rawValue)
                LabeledContent("Push token state", value: device.pushTokenState ?? "none registered")
                LabeledContent("Can receive notifications", value: device.canReceiveNotifications ? "yes" : "no")
                LabeledContent("Last seen", value: Self.text(device.lastSeenAt))
            }
            if let push = models.pushRegistration {
                LabeledContent("Token from the system", value: push.hasToken ? "received" : "not yet")
                LabeledContent("Token sent", value: Self.text(push.lastRegisteredAt))
                if let outcome = push.lastOutcome {
                    LabeledContent("Last registration", value: outcome.summary)
                }
            }
        }
    }

    private var notificationsSection: some View {
        let settings = models.notificationSettings
        return Section("Notification Permission") {
            LabeledContent("Authorization", value: settings.permission?.authorization.rawValue ?? "not read")
            ForEach(Self.lines(of: settings.permission?.settings ?? [:]), id: \.self) { line in
                Text(verbatim: line)
                    .font(.footnote.monospaced())
            }
            LabeledContent("Reported", value: Self.text(settings.lastReportedAt))
            LabeledContent("Report waiting", value: settings.reportPending ? "yes" : "no")
            if let report = settings.lastReport {
                LabeledContent("Last report", value: report.summary)
            }
            if let revision = settings.displayed?.revision {
                LabeledContent("Preferences revision", value: "\(revision)")
            }
        }
    }

    private var queueSection: some View {
        let queue = models.pendingActions
        let entries = queue.pending + queue.conflicts + queue.failures
        return Section("Offline Queue") {
            LabeledContent(
                "Entries",
                value: "\(queue.pending.count) waiting, \(queue.conflicts.count) conflicts, "
                    + "\(queue.failures.count) failed")
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
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if let result = models.rundown.state.result {
                let rundown = result.value
                Text(
                    verbatim: "rundown \(rundown.planID) r\(rundown.revision) \(rundown.date) \(rundown.zone), "
                        + "\(result.source) at \(Self.text(result.fetchedAt))")
            }
            if let result = models.brief.state.result {
                let brief = result.value
                Text(
                    verbatim: "brief \(brief.briefID) r\(brief.revision) v\(brief.version) \(brief.state)"
                        + "\(brief.templateOnly ? " template-only" : ""), \(result.source) at "
                        + Self.text(result.fetchedAt))
            }
            if let result = models.tasks.state.result {
                Text(verbatim: "tasks \(result.value.items.count), \(result.source) at \(Self.text(result.fetchedAt))")
            }
            if let reminders = models.reminders.state.value {
                Text(verbatim: "reminders \(reminders.count)")
            }
        }
        .font(.caption.monospaced())
    }

    // MARK: - Text

    private var trustText: String {
        guard let trust = models.hostConnection.trust else { return "system trust store" }
        let pinned = trust.leafCertificateSHA256 == nil ? "" : ", host certificate pinned"
        return "\(trust.anchorCertificates.count) owner certificate(s)\(pinned)"
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
