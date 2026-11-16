// `lisa status`: runtime health, delivery modes, outbox counts and source freshness.

import ArgumentParser
import Foundation
import LisaAPIContract

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Report runtime and source state.")

    @OptionGroup var host: HostOptions

    func run() async throws {
        let health = try await HostSession.withOwner(host) { _, client in try await client.health() }
        try host.output.emit(health) { health in
            var lines = [
                "status: \(health.status) (Lisa \(health.applicationVersion), schema \(health.schemaVersion))",
                "delivery: "
                    + health.deliveryModes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(
                        separator: ", "),
                "outbox: \(health.outbox.pending) pending, \(health.outbox.inProgress) in progress, "
                    + "\(health.outbox.outcomeUnknown) uncertain, \(health.outbox.failed) failed, "
                    + "\(health.outbox.capturedDryRun) captured as dry runs",
            ]
            lines += health.sources.map { source in
                "source \(source.name): \(source.freshness)"
                    + (source.failing ? ", failing (\(source.failureClass ?? "")): \(source.failureSummary ?? "")" : "")
            }
            lines += health.deviceWarnings.map { "device: \($0)" }
            lines += health.warnings.map { "warning: \($0)" }
            if let problem = health.lastCycleProblem { lines.append("last cycle: \(problem)") }
            return lines.joined(separator: "\n")
        }
    }
}
