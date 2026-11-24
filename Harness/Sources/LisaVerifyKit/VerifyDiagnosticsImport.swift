// `import-diagnostics <run-id> <file>` (plan §10.8 "Commands"): a device's exported `results.jsonl` or
// `evidence.jsonl` (the X1 proof app's, or the production Diagnostics export later) joins the run. Result lines must
// belong to the run and name a known case; an evidence file is kept under `evidence/` by its digest and never
// overwrites another.

import Foundation
import LisaCrypto

/// Imports a device's exported file into a run.
public enum VerifyDiagnosticsImport {
    public struct Outcome: Sendable, Equatable {
        public var resultsAdded = 0
        public var resultsAlreadyPresent = 0
        public var evidenceFile: String?
    }

    /// - Parameter knownCase: whether a (base) case ID is in the catalogue.
    public static func importFile(
        _ file: URL, into run: VerifyRunID, store: VerifyRunStore, knownCase: (VerifyCaseID) -> Bool
    ) throws(VerifyError) -> Outcome {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw .invalidInput("can't read \(file.path)")
        }
        _ = try store.load(run)
        let lines = data.split(separator: UInt8(ascii: "\n")).filter { !$0.isEmpty }
        let records = lines.compactMap { try? JSONDecoder().decode(VerifyResultRecord.self, from: Data($0)) }
        var outcome = Outcome()
        if !lines.isEmpty, records.count == lines.count {
            let existing = try store.results(of: run)
            for record in records {
                guard record.runID == run.text else {
                    throw .invalidInput("\(file.lastPathComponent) has a result of run \(record.runID), not \(run)")
                }
                let (caseID, _) = try VerifyCaseID.parseCorrelated(record.caseID)
                guard knownCase(caseID) else { throw .unknownCase(caseID.text) }
            }
            for record in records {
                if existing.contains(record) {
                    outcome.resultsAlreadyPresent += 1
                } else {
                    try store.append(record, to: run)
                    outcome.resultsAdded += 1
                }
            }
            return outcome
        }
        let digest = Digests.sha256Hex(data)
        let name = "\(digest.prefix(16))-\(file.lastPathComponent)"
        let target = store.evidenceDirectory(of: run).appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) {
            guard
                FileManager.default.createFile(
                    atPath: target.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { throw .store("can't write \(target.path)") }
        }
        outcome.evidenceFile = name
        return outcome
    }
}
