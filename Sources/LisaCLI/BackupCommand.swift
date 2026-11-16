// `lisa backup`: a consistent copy of the database with its manifest (DATA-05, CFG-03).

import ArgumentParser
import Foundation
import LisaPorts

struct BackupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "backup", abstract: "Back up the data store.")

    @OptionGroup var host: HostOptions

    @Option(help: "The directory for the backup and its manifest.")
    var output: String

    func run() async throws {
        let lisa = try HostSession.open(host)
        defer { lisa.close() }
        let manifest = try lisa.backup(to: URL(fileURLWithPath: (output as NSString).expandingTildeInPath))
        try host.output.emit(manifest) { manifest in
            "backed up schema \(manifest.schemaVersion) (\(manifest.recordCounts.values.reduce(0, +)) records) to \(output)"
        }
    }
}
