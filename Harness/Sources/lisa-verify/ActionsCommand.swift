// `lisa-verify actions <run-id>` (plan §10.8): the run's action ledger. Provider references are shown only as
// digests.

import ArgumentParser
import Foundation
import LisaVerifyKit

struct ActionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "actions", abstract: "List the run's logical actions.")

    @Argument(help: "The run ID.") var runID: String
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let store = storeOptions.store
        let run = try VerifyRunID(runID)
        _ = try store.load(run)
        let path = store.ledgerPath(of: run)
        guard FileManager.default.fileExists(atPath: path) else {
            print("No logical actions in \(run).")
            return
        }
        let redactor = VerifyRedactor()
        let records = try VerifyActionLedger(path: path).records(in: run)
        for record in records {
            let reference = record.providerReference.map(redactor.digest) ?? "—"
            print(
                "\(record.actionID)\t\(record.kind.rawValue)\t\(record.targetAlias)\t\(record.state.rawValue)\t"
                    + "\(record.outcome ?? "—")\t\(reference)")
        }
        print("\(records.count) action\(records.count == 1 ? "" : "s")")
    }
}
