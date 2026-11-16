// `lisa import`: imports a local directory of mail (.eml), calendars (.ics) or feeds once; re-imports deduplicate.

import ArgumentParser
import Foundation
import LisaHost
import LisaLocalSources

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: "Import supported local source files (mail, calendar or feed).")

    @OptionGroup var host: HostOptions

    @Option(help: "What the directory holds: mail, calendar or feed.")
    var format: LocalSourceFormat

    @Option(help: "A stable key for this import source (re-using it continues where the last import stopped).")
    var key: String = "local-import"

    @Argument(help: "The directory to import.")
    var directory: String

    struct Summary: Encodable {
        var inserted: Int
        var unchanged: Int
        var updated: Int
        var skipped: Int
        var failure: String?
        var warnings: [String]
    }

    func run() async throws {
        let lisa = try HostSession.open(host)
        defer { lisa.close() }
        let url = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        let report = try await lisa.importDirectory(url, format: format, key: key, name: "Local import (\(key))")
        let summary = Summary(
            inserted: report.outcome.inserted, unchanged: report.outcome.unchanged, updated: report.outcome.updated,
            skipped: report.outcome.skipped, failure: report.failure.map { "\($0.errorClass.rawValue): \($0.summary)" },
            warnings: report.outcome.warnings)
        try host.output.emit(summary) { summary in
            var lines = [
                "imported: \(summary.inserted) new, \(summary.unchanged) already known, \(summary.updated) changed"
            ]
            if summary.skipped > 0 { lines.append("skipped: \(summary.skipped)") }
            lines += summary.warnings.map { "warning: \($0)" }
            if let failure = summary.failure { lines.append("failed: \(failure)") }
            return lines.joined(separator: "\n")
        }
        if report.failure != nil { throw LisaExit.failure }
    }
}

extension LocalSourceFormat: ExpressibleByArgument {}
