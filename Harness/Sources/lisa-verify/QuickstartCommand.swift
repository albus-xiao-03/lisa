// `lisa-verify quickstart` (plan §10.8 `README.md`): from a clean clone, creates `~/LisaVerify/config.json5` from the
// example (never overwriting yours), runs the Apple preflight, lists the cases and prints the first fixture run and
// the first owner session.

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct QuickstartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quickstart", abstract: "Set up ~/LisaVerify, run the preflight and list the cases.")

    @Option(help: "The configuration example to copy.") var example = "Harness/config/owner-verify.example.json5"
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let home = storeOptions.store.home
        try FileManager.default.createDirectory(
            at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = home.appendingPathComponent("config.json5")
        if FileManager.default.fileExists(atPath: config.path) {
            print("Kept your configuration: \(config.path)")
        } else {
            guard let data = FileManager.default.contents(atPath: example) else {
                throw VerifyError.invalidInput("can't read \(example); run quickstart from the repository's root")
            }
            guard
                FileManager.default.createFile(
                    atPath: config.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { throw VerifyError.store("can't write \(config.path)") }
            print("Created \(config.path) from the example: replace its placeholders with your own values.")
        }
        print("")
        try PreflightCommand.parse(["apple"]).run()
        print("")
        for verifyCase in VerifyCatalogue.all {
            print("\(verifyCase.id)\t\(verifyCase.session ?? "fixture")\t\(verifyCase.title)")
        }
        print("")
        print("First fixture run (no account, no device):  swift run lisa-verify run --mode fixture")
        print(
            "First owner session (X1, Harness/docs/SETUP-APPLE.md):  swift run lisa-verify pair-session OV-NEAR-MI-01 "
                + "--devices mac,iphone --condition shared-wifi")
    }
}
