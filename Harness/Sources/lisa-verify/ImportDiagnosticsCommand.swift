// `lisa-verify import-diagnostics <run-id> <file>` (plan §10.8): a device's exported results or evidence joins the
// run.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct ImportDiagnosticsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-diagnostics", abstract: "Import a device's exported results.jsonl or evidence file.")

    @Argument(help: "The run ID.") var runID: String
    @Argument(help: "The exported file.") var file: String
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let run = try VerifyRunID(runID)
        let known = Set(VerifyCatalogue.all.map(\.id))
        let outcome = try VerifyDiagnosticsImport.importFile(
            URL(fileURLWithPath: file), into: run, store: storeOptions.store
        ) { known.contains($0) }
        if let evidence = outcome.evidenceFile {
            print("Kept as evidence: \(evidence)")
        } else {
            print("Results added: \(outcome.resultsAdded); already present: \(outcome.resultsAlreadyPresent)")
        }
    }
}
