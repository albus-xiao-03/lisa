// `lisa-verify report <run-id>` (plan §10.8): writes and prints the run's `summary.md`.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "report", abstract: "Write the run's summary.md.")

    @Argument(help: "The run ID.") var runID: String
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let store = storeOptions.store
        let run = try store.load(try VerifyRunID(runID))
        let results = try store.results(of: run.id)
        let selected = Set(run.selection)
        let named = Set(results.compactMap { try? VerifyCaseID.parseCorrelated($0.caseID).0 })
        let cases = VerifyCatalogue.all.filter { selected.contains($0.id) || named.contains($0.id) }
        let summary = VerifyReport.summary(run: run, results: results, cases: cases)
        let file = store.directory(of: run.id).appendingPathComponent("summary.md")
        try Data(summary.utf8).write(to: file, options: .atomic)
        print(summary)
        print("Written: \(file.path)")
    }
}
