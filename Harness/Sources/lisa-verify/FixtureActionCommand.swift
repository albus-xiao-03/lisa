// `lisa-verify fixture-action` (internal, used by S-24's fixture cases): performs one fixture action of a run under
// the ledger's rules against the controlled servers, optionally killing itself at a crash point.

import ArgumentParser
import LisaVerifyCases
import LisaVerifyKit

struct FixtureActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fixture-action", abstract: "Internal: perform one fixture action (S-24).", shouldDisplay: false)

    @Option var run: String
    @Option(name: .customLong("case")) var caseID: String
    @Option var kind: String
    @Option var position: Int
    @Option var smtpPort: Int
    @Option var httpPort: Int
    @Option var crashAt: String?
    @Flag var requireConfirmation = false
    @OptionGroup var storeOptions: StoreOptions

    func run() async throws {
        let store = storeOptions.store
        let runID = try VerifyRunID(run)
        _ = try store.load(runID)
        guard let kind = VerifyActionKind(rawValue: kind) else {
            throw VerifyError.invalidInput("unknown kind \(kind)")
        }
        let crash = try crashAt.map { value in
            guard let point = FixtureCrashPoint(rawValue: value) else {
                throw VerifyError.invalidInput("unknown crash point \(value)")
            }
            return point
        }
        let planned = FixtureActionExecutor.plannedAction(
            case: try VerifyCaseID(caseID), kind: kind, position: position, in: runID)
        let ledger = try VerifyActionLedger(path: store.ledgerPath(of: runID))
        let record = try await FixtureActionExecutor.perform(
            planned, in: runID, ledger: ledger, endpoints: FixtureEndpoints(smtpPort: smtpPort, httpPort: httpPort),
            requireConfirmation: requireConfirmation, crashAt: crash)
        print("\(record.actionID) \(record.state.rawValue) \(record.outcome ?? "")")
    }
}
