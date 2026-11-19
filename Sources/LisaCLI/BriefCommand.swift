// `lisa brief`: shows (and optionally regenerates) the readable or spoken brief.

import ArgumentParser
import Foundation
import LisaAPIContract

struct BriefCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "brief", abstract: "Generate or inspect a brief.")

    @OptionGroup var host: HostOptions

    @Option(help: "The local date, YYYY-MM-DD (default: today).")
    var date: String?

    @Flag(help: "Print the spoken version.")
    var spoken = false

    @Flag(help: "Compose a new version first (no second notification is sent).")
    var regenerate = false

    func run() async throws {
        let brief = try await HostSession.withOwner(host) { _, client in
            regenerate ? try await client.regenerateBrief(date: date) : try await client.brief(date: date)
        }
        try host.output.emit(brief) { brief in
            let header =
                "Brief for \(brief.date) — version \(brief.version), \(brief.state)"
                + (brief.lastFailure.map { " (last regeneration failed: \($0))" } ?? "")
            return header + "\n\n" + (spoken ? brief.spokenText : brief.text)
        }
    }
}
