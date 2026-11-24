// `lisa-verify observe <run-id> <case> --status pass|fail --observed "…"` (plan §10.8): a manual observation,
// recorded like any other result, with the digest of each evidence file.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct ObserveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "observe", abstract: "Record a manual observation.")

    @Argument(help: "The run ID.") var runID: String
    @Argument(help: "The case ID, or <case>@<role> for one device of a paired case.") var caseID: String
    @Option(help: "pass | fail") var status: String
    @Option(help: "What you observed.") var observed: String
    @Option(help: "An evidence file (repeatable); its SHA-256 is recorded.") var evidence: [String] = []
    @Option(help: "The platform observed (default: this host's).") var platform: String?
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let store = storeOptions.store
        let run = try store.load(try VerifyRunID(runID))
        let (id, role) = try VerifyCaseID.parseCorrelated(caseID)
        let verifyCase = try VerifyCatalogue.find(id)
        if role != nil, !verifyCase.paired { throw VerifyError.invalidInput("\(id) is not a paired case") }
        let verdict: VerifyStatus
        switch status.lowercased() {
        case "pass": verdict = .pass
        case "fail": verdict = .fail
        default: throw VerifyError.invalidInput("--status must be pass or fail")
        }
        let record = try VerifyObservation.record(
            run: run, case: verifyCase, correlatedCaseID: caseID, status: verdict, observed: observed,
            evidenceFiles: evidence.map { URL(fileURLWithPath: $0) }, platform: platform ?? HarnessInfo.platform,
            commit: HarnessInfo.commit(), harnessVersion: HarnessInfo.version)
        try store.append(record, to: run.id)
        print("Recorded \(caseID): \(verdict.rawValue) in \(run.id)")
        for name in record.evidenceFiles { print("  evidence \(name)") }
    }
}
