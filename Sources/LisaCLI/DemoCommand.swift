// `lisa demo`: the offline end-to-end demonstration in its own data directory (DEMO-01).

import ArgumentParser
import Foundation
import LisaDemo

struct DemoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "Run the synthetic end-to-end scenario without accounts, credentials or network access.",
        discussion:
            "Uses its own new or empty data directory, synthetic identities and the bundled fixtures. Nothing is sent.")

    @Option(name: .customLong("data-dir"), help: "A new or empty directory for the demonstration's data.")
    var dataDirectory: String?

    @Flag(help: "Print the report as JSON.")
    var json = false

    func run() async throws {
        let directory =
            dataDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lisa-demo-\(UUID().uuidString.prefix(8))")
        let report: DemoReport
        do {
            report = try await DemoScenario.run(dataDirectory: directory, applicationVersion: LisaVersion.current)
        } catch let error as DemoError {
            Output.error(error.description)
            throw LisaExit.failure
        }
        try Output(json: json).emit(report) { $0.text }
        if !report.passed { throw LisaExit.checksFailed }
    }
}
