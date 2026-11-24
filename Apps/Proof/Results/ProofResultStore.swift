// PROOF ONLY — Apps/Proof never ships. The run's files on this device, in the app's Documents folder under
// `LisaProof/<run-id>/`: `evidence.jsonl` and `results.jsonl`, both append-only (a line is never rewritten). The owner
// exports them from the Results tab or the Files app and imports them with `lisa-verify import-diagnostics`
// (plan §10.8). They hold synthetic identifiers, public keys' hashes and timings only, never a secret.

import Foundation

struct ProofResultStore: Sendable {
    static let evidenceFile = "evidence.jsonl"
    static let resultsFile = "results.jsonl"

    let directory: URL

    enum Failure: Error, Equatable {
        case invalidRunID
    }

    init(runID: String) throws {
        guard runID.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else {
            throw Failure.invalidRunID
        }
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = documents.appendingPathComponent("LisaProof", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(_ entry: ProofEvidenceEntry) throws {
        try appendLine(try Self.encoder.encode(entry), to: Self.evidenceFile)
    }

    func append(_ record: ProofResultRecord) throws {
        try appendLine(try Self.encoder.encode(record), to: Self.resultsFile)
    }

    func evidence() -> [ProofEvidenceEntry] {
        lines(Self.evidenceFile).compactMap { try? JSONDecoder().decode(ProofEvidenceEntry.self, from: $0) }
    }

    func results() -> [ProofResultRecord] {
        lines(Self.resultsFile).compactMap { try? JSONDecoder().decode(ProofResultRecord.self, from: $0) }
    }

    func url(of file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func appendLine(_ data: Data, to file: String) throws {
        let target = url(of: file)
        if !FileManager.default.fileExists(atPath: target.path) {
            _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data + Data([0x0A]))
    }

    private func lines(_ file: String) -> [Data] {
        guard let data = try? Data(contentsOf: url(of: file)) else { return [] }
        return data.split(separator: 0x0A).map { Data($0) }
    }
}
