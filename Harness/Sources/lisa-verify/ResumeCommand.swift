// `lisa-verify resume <run-id>` (plan §10.8 "The action ledger" step 3): observes and reconciles every action without
// a recorded outcome and never resends one that reached `submitting`. A fixture run names its controlled servers'
// ports; an owner run lists what waits for the owner.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resume", abstract: "Resume a run.")

    @Argument(help: "The run ID.") var runID: String
    @Option(help: "A fixture run's controlled SMTP port.") var smtpPort: Int?
    @Option(help: "A fixture run's controlled HTTP port.") var httpPort: Int?
    @OptionGroup var storeOptions: StoreOptions

    func run() async throws {
        let store = storeOptions.store
        let run = try store.load(try VerifyRunID(runID))
        let ledgerPath = store.ledgerPath(of: run.id)
        if let smtpPort, let httpPort {
            let ledger = try VerifyActionLedger(path: ledgerPath)
            let records = try await FixtureActionExecutor.resume(
                run: run.id, ledger: ledger, endpoints: FixtureEndpoints(smtpPort: smtpPort, httpPort: httpPort))
            for record in records { print("\(record.actionID) \(record.state.rawValue) \(record.outcome ?? "")") }
            return
        }
        if FileManager.default.fileExists(atPath: ledgerPath) {
            let unresolved = try VerifyActionLedger(path: ledgerPath).unresolved(in: run.id)
            guard unresolved.isEmpty else {
                throw VerifyError.invalidInput(
                    "\(unresolved.count) action(s) need their servers to reconcile; give --smtp-port and --http-port")
            }
        }
        let waiting = run.selection.filter { run.state(of: $0) != .completed }
        print("Run \(run.id): \(waiting.count) case(s) not completed")
        for id in waiting { print("  \(id) \(run.state(of: id).rawValue) — lisa-verify guide \(id)") }
    }
}
