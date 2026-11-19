// `lisa export`: writes versioned JSON of all owner data, without credentials, verifiers or push tokens.

import ArgumentParser
import Foundation

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Export supported owner data.")

    @OptionGroup var host: HostOptions

    @Option(help: "Write to this file (owner-only permissions) instead of standard output.")
    var output: String?

    func run() async throws {
        let data = try await HostSession.withOwner(host) { _, client in try await client.export() }
        guard let output else {
            FileHandle.standardOutput.write(data)
            return
        }
        let url = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        print("exported \(data.count) bytes to \(url.path)")
    }
}
