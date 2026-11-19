// `lisa run-once`: one bounded processing cycle (sources, review, planning, reminders, brief, outbox).

import ArgumentParser
import Foundation
import LisaHost
import LisaRuntime

struct RunOnceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-once", abstract: "Perform one bounded processing cycle, then exit.")

    @OptionGroup var host: HostOptions

    struct Summary: Encodable {
        var sources: [String]
        var remindersFired: Int
        var deliveriesClaimed: Int
        var briefDispatched: Bool
        var problem: String?
        var recovery: [String]
    }

    func run() async throws {
        let lisa = try HostSession.open(host)
        defer { lisa.close() }
        let outcome = await lisa.runtime.runOnce()
        let summary = Summary(
            sources: outcome.synchronized.map { report in
                report.failure.map { "failed (\($0.errorClass.rawValue)): \($0.summary)" }
                    ?? "\(report.outcome.inserted) new, \(report.outcome.unchanged) known, \(report.outcome.updated) changed"
            },
            remindersFired: outcome.cycle?.remindersFired ?? 0,
            deliveriesClaimed: outcome.cycle?.deliveries.claimed ?? 0,
            briefDispatched: outcome.cycle?.brief != nil, problem: outcome.problem, recovery: lisa.recoveryNotes)
        try host.output.emit(summary) { summary in
            (summary.sources.map { "source: \($0)" } + [
                "reminders fired: \(summary.remindersFired)", "deliveries processed: \(summary.deliveriesClaimed)",
                "brief dispatched: \(summary.briefDispatched ? "yes" : "no")",
            ] + summary.recovery.map { "recovery: \($0)" } + (summary.problem.map { ["problem: \($0)"] } ?? []))
            .joined(separator: "\n")
        }
        if outcome.problem != nil { throw LisaExit.failure }
    }
}
