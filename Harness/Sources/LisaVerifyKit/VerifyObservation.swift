// A manual observation recorded like any other result (plan §10.8 `observe <run-id> <case> --status pass|fail
// --observed "…"`): the owner's own observation, with the SHA-256 of any evidence file named, such as a build log.

import Foundation
import LisaCrypto

/// Builds the result record of an owner's observation.
public enum VerifyObservation {
    public static func record(
        run: VerifyRun, case verifyCase: VerifyCase, correlatedCaseID: String, status: VerifyStatus, observed: String,
        evidenceFiles: [URL], platform: String, commit: String, harnessVersion: String
    ) throws(VerifyError) -> VerifyResultRecord {
        var names: [String] = []
        for file in evidenceFiles {
            guard let data = FileManager.default.contents(atPath: file.path) else {
                throw .invalidInput("can't read evidence file \(file.path)")
            }
            names.append("\(file.lastPathComponent) sha256:\(Digests.sha256Hex(data))")
        }
        let now = VerifyClock.wallClock()
        let tick = VerifyClock.monotonicNanoseconds()
        return VerifyResultRecord(
            runID: run.id.text, caseID: correlatedCaseID, commit: commit, harnessVersion: harnessVersion,
            providerInterface: verifyCase.interface,
            configuration: .init(digest: Digests.sha256Hex(Data(verifyCase.environment.utf8)), fields: [:]),
            platform: platform, deviceModel: "", osVersion: "", xcodeVersion: "", assumptions: [],
            requiredEvidence: verifyCase.requiredEvidence, expectedResult: verifyCase.expectedOutcome,
            observedResult: observed, resultLevel: status == .pass ? verifyCase.requiredResultLevel : nil,
            requiredResultLevel: verifyCase.requiredResultLevel, status: status, executor: verifyCase.executor,
            cause: status == .pass ? "observed by the \(verifyCase.executor.rawValue)" : observed, actions: [],
            times: .init(
                wallClockStart: now, wallClockEnd: now, monotonicStartNanoseconds: tick, monotonicEndNanoseconds: tick),
            evidenceFiles: names)
    }
}
