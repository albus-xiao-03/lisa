// `lisa-verify export <run-id> --redacted <file>` (plan §10.8): the only form of a run's results meant to leave the
// owner's machine. Canaries named in `--canaries` (one per line) must not survive, or nothing is written.

import ArgumentParser
import Foundation
import LisaVerifyKit

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Write a redacted export.")

    @Argument(help: "The run ID.") var runID: String
    @Option(help: "The export file to write (refused if it exists).") var redacted: String
    @Option(help: "A file of planted canaries, one per line, that must not appear in the export.") var canaries: String?
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let store = storeOptions.store
        let run = try store.load(try VerifyRunID(runID))
        let ledgerPath = store.ledgerPath(of: run.id)
        let actions =
            FileManager.default.fileExists(atPath: ledgerPath)
            ? try VerifyActionLedger(path: ledgerPath).records(in: run.id) : []
        var planted: [String] = []
        if let canaries {
            guard let data = FileManager.default.contents(atPath: canaries) else {
                throw VerifyError.invalidInput("can't read \(canaries)")
            }
            planted = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        }
        let data = try VerifyRedactedExport.make(
            run: run, results: try store.results(of: run.id), actions: actions, canaries: planted)
        guard !FileManager.default.fileExists(atPath: redacted) else {
            throw VerifyError.invalidInput("\(redacted) exists; choose a new file")
        }
        guard FileManager.default.createFile(atPath: redacted, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw VerifyError.store("can't write \(redacted)") }
        print("Redacted export written: \(redacted) (\(data.count) bytes; \(planted.count) canaries checked)")
    }
}
