// `lisa-verify retry <run-id> <case>` (plan §10.8): reruns one case alone; its earlier results stay, other cases are
// untouched, and its new logical actions get new positions (a live case would need a new confirmation for them).

import ArgumentParser
import LisaVerifyCases
import LisaVerifyKit

struct RetryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "retry", abstract: "Rerun one case of a run.")

    @Argument(help: "The run ID.") var runID: String
    @Argument(help: "The case ID.") var caseID: String
    @OptionGroup var storeOptions: StoreOptions

    func run() async throws {
        let store = storeOptions.store
        var run = try store.load(try VerifyRunID(runID))
        let verifyCase = try VerifyCatalogue.find(try VerifyCaseID(caseID))
        guard run.mode == .fixture, verifyCase.modes.contains(.fixture) else {
            throw VerifyError.invalidInput("retry reruns fixture cases here; an owner case is rerun by its guide")
        }
        if !run.selection.contains(verifyCase.id) { run.selection.append(verifyCase.id) }
        let attempt = try store.results(of: run.id).filter { $0.caseID == verifyCase.id.text }.count
        let record = try await FixtureCaseRunner.execute(
            verifyCase, run: &run, store: store, home: store.home.path, attempt: attempt)
        if record.status != .pass { throw ExitCode(1) }
    }
}
