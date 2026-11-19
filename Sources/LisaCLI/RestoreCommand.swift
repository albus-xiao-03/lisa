// `lisa restore`: restores a backup into a data directory that no host holds, keeping the replaced database.

import ArgumentParser
import Foundation
import LisaHost
import LisaRuntime

struct RestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore", abstract: "Restore a backup into the data directory (no host may be running).")

    @OptionGroup var host: HostOptions

    @Argument(help: "The backup file (lisa-backup-<timestamp>.sqlite).")
    var backup: String

    func run() async throws {
        let settings = try HostSession.settings(try HostSession.configuration(host), host)
        do {
            let report = try LisaHost.restore(
                backupFile: URL(fileURLWithPath: (backup as NSString).expandingTildeInPath),
                dataDirectory: settings.dataDirectory, now: Date())
            print(
                "restored schema \(report.restoredSchemaVersion)"
                    + (report.previousDatabaseMovedTo.map { "; the replaced database was kept at \($0)" } ?? ""))
        } catch let error as RuntimeError {
            Output.error(error.description)
            throw LisaExit.dataDirectoryInUse
        }
    }
}
