// Lisa's runtime state as the settings screen shows it: the overall status, start and last cycle, problems, warnings
// and the delivery outbox, with versions kept for diagnostics.

import Foundation
import LisaAPIContract

/// The host's runtime state from `GET /v1/health` (UI-01: runtime state) in plain words. The versions are diagnostics
/// and stay out of the daily flow.
public struct RuntimeStateSummary: Hashable, Sendable {
    /// The overall status.
    public enum Level: Hashable, Sendable {
        /// Everything works.
        case ok
        /// Lisa runs, but a source, a delivery, a device or the runtime needs attention.
        case degraded
        /// The last processing cycle failed.
        case failing
        /// A status this app does not know, with the host's word for it.
        case other(String)

        /// The level of the host's `status`.
        public init(_ status: String) {
            switch status {
            case "ok": self = .ok
            case "degraded": self = .degraded
            case "failing": self = .failing
            default: self = .other(status)
            }
        }
    }

    /// The overall status.
    public var level: Level
    /// A sentence about the overall status.
    public var message: String
    /// When the host started.
    public var startedAt: Date
    /// When the last processing cycle ran.
    public var lastCycleAt: Date?
    /// Why the last processing cycle failed, if it did.
    public var lastCycleProblem: String?
    /// The runtime's warnings.
    public var warnings: [String]
    /// Deliveries by state.
    public var outbox: OutboxSummaryDTO
    /// A sentence about deliveries that wait, failed, may or may not have gone out, or were only recorded in dry run.
    public var outboxMessage: String
    /// Diagnostics: the host application's version.
    public var applicationVersion: String
    /// Diagnostics: the API version the host speaks.
    public var apiVersion: String
    /// Diagnostics: the version of the host's store.
    public var schemaVersion: Int

    /// The runtime state `health` reports.
    public init(_ health: HealthDTO) {
        level = Level(health.status)
        message =
            switch level {
            case .ok: "Lisa is running normally."
            case .degraded: "Lisa is running, but something needs your attention."
            case .failing: "Lisa's last processing cycle failed."
            case .other(let status): "Lisa reports the status \"\(status)\"."
            }
        startedAt = health.startedAt
        lastCycleAt = health.lastCycleAt
        lastCycleProblem = health.lastCycleProblem
        warnings = health.warnings
        outbox = health.outbox
        outboxMessage = Self.outboxMessage(health.outbox)
        applicationVersion = health.applicationVersion
        apiVersion = health.apiVersion
        schemaVersion = health.schemaVersion
    }

    /// Whether something needs the owner's attention.
    public var needsAttention: Bool {
        level != .ok || !warnings.isEmpty || outbox.failed > 0 || outbox.outcomeUnknown > 0
    }

    /// How long the host has been running at `now`, in words such as "3 hours".
    public func uptimePhrase(at now: Date) -> String {
        AgePhrase.english(now.timeIntervalSince(startedAt))
    }

    /// When the last processing cycle ran, in words such as "Last cycle 5 minutes ago", or that none ran yet.
    public func lastCyclePhrase(at now: Date) -> String {
        guard let lastCycleAt else { return "No processing cycle has run yet." }
        return "Last cycle \(AgePhrase.english(now.timeIntervalSince(lastCycleAt))) ago."
    }

    private static func outboxMessage(_ outbox: OutboxSummaryDTO) -> String {
        var parts: [String] = []
        let waiting = outbox.pending + outbox.inProgress
        if waiting > 0 { parts.append("\(waiting) waiting to be delivered") }
        if outbox.outcomeUnknown > 0 {
            parts.append("\(outbox.outcomeUnknown) that may or may not have been delivered")
        }
        if outbox.failed > 0 { parts.append("\(outbox.failed) failed") }
        if outbox.capturedDryRun > 0 { parts.append("\(outbox.capturedDryRun) recorded in dry run and not sent") }
        return parts.isEmpty ? "No deliveries are waiting." : "Deliveries: " + parts.joined(separator: "; ") + "."
    }
}
