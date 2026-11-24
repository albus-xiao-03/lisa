// The resumable run store (plan §10.8): `~/LisaVerify/runs/<run-id>/` with `run.json`, the ledger `actions.sqlite`,
// `results.jsonl` and `evidence/`. Results stay on the owner's machine and never enter the repository.

import Foundation

/// The harness's local store. Run directories are created owner-only; `run.json` is replaced atomically and
/// `results.jsonl` is append-only.
public struct VerifyRunStore: Sendable {
    /// The harness home, `~/LisaVerify` unless `LISA_VERIFY_HOME` names another directory.
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["LISA_VERIFY_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("LisaVerify", isDirectory: true)
    }

    public var runsDirectory: URL { home.appendingPathComponent("runs", isDirectory: true) }

    public func directory(of run: VerifyRunID) -> URL {
        runsDirectory.appendingPathComponent(run.text, isDirectory: true)
    }

    public func ledgerPath(of run: VerifyRunID) -> String {
        directory(of: run).appendingPathComponent("actions.sqlite").path
    }

    public func evidenceDirectory(of run: VerifyRunID) -> URL {
        directory(of: run).appendingPathComponent("evidence", isDirectory: true)
    }

    /// Creates a new run's directory and `run.json`; refuses an existing run.
    public func create(_ run: VerifyRun) throws(VerifyError) {
        let directory = directory(of: run.id)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw .store("run \(run.id) already exists")
        }
        do {
            try FileManager.default.createDirectory(
                at: evidenceDirectory(of: run.id), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            throw .store("can't create \(directory.path): \(error)")
        }
        try save(run)
    }

    public func load(_ id: VerifyRunID) throws(VerifyError) -> VerifyRun {
        let file = directory(of: id).appendingPathComponent("run.json")
        guard let data = FileManager.default.contents(atPath: file.path) else { throw .runNotFound(id.text) }
        do {
            return try JSONDecoder().decode(VerifyRun.self, from: data)
        } catch {
            throw .store("run.json of \(id) is unreadable: \(error)")
        }
    }

    /// Replaces `run.json` atomically.
    public func save(_ run: VerifyRun) throws(VerifyError) {
        let file = directory(of: run.id).appendingPathComponent("run.json")
        do {
            try Self.encoder().encode(run).write(to: file, options: .atomic)
        } catch {
            throw .store("can't write \(file.path): \(error)")
        }
    }

    /// Appends one result line and flushes it to storage before returning.
    public func append(_ record: VerifyResultRecord, to run: VerifyRunID) throws(VerifyError) {
        let file = directory(of: run).appendingPathComponent("results.jsonl")
        do {
            var line = try Self.encoder().encode(record)
            line.append(UInt8(ascii: "\n"))
            if !FileManager.default.fileExists(atPath: file.path) {
                guard
                    FileManager.default.createFile(
                        atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
                else { throw VerifyError.store("can't create \(file.path)") }
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.synchronize()
        } catch let error as VerifyError {
            throw error
        } catch {
            throw .store("can't append to \(file.path): \(error)")
        }
    }

    /// Every result line of a run, in order.
    public func results(of run: VerifyRunID) throws(VerifyError) -> [VerifyResultRecord] {
        let file = directory(of: run).appendingPathComponent("results.jsonl")
        guard let data = FileManager.default.contents(atPath: file.path) else { return [] }
        var records: [VerifyResultRecord] = []
        for (index, line) in data.split(separator: UInt8(ascii: "\n")).enumerated() where !line.isEmpty {
            do {
                records.append(try JSONDecoder().decode(VerifyResultRecord.self, from: Data(line)))
            } catch {
                throw .store("results.jsonl line \(index + 1) of \(run) is unreadable: \(error)")
            }
        }
        return records
    }

    /// The runs in the store, oldest first.
    public func runs() -> [VerifyRunID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: runsDirectory.path)) ?? []
        return names.compactMap { try? VerifyRunID($0) }.sorted()
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
