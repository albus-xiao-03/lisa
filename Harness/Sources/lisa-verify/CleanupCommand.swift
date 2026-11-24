// `lisa-verify cleanup <run-id>` (plan §10.8 "Owner resources, cleanup and revocation"): lists what the run created
// and removes what the harness itself holds — the run's own directory in the store, nothing else. Provider-side items
// are the owner's to remove in the provider's UI (CLEANUP.md); the verification Core's container and volume join this
// command at M3, behind the stopped-target check.

import ArgumentParser
import Foundation
import LisaVerifyKit

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cleanup", abstract: "Remove a run's local data.")

    @Argument(help: "The run ID.") var runID: String
    @Flag(help: "Remove without asking (otherwise type the run ID to confirm).") var yes = false
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let store = storeOptions.store
        let run = try VerifyRunID(runID)
        _ = try store.load(run)
        let directory = store.directory(of: run).standardizedFileURL
        guard directory.deletingLastPathComponent().path == store.runsDirectory.standardizedFileURL.path else {
            throw VerifyError.store("refusing to remove \(directory.path): not a run directory of this store")
        }
        let items = (FileManager.default.enumerator(atPath: directory.path)?.allObjects as? [String]) ?? []
        print("Run \(run) created \(items.count) local item\(items.count == 1 ? "" : "s") under \(directory.path):")
        for item in items.sorted() { print("  \(item)") }
        if !yes {
            print("Type the run ID to remove them:")
            guard readLine(strippingNewline: true) == run.text else {
                print("Nothing removed.")
                return
            }
        }
        try FileManager.default.removeItem(at: directory)
        print("Removed \(directory.path). Provider-side items, if any, are listed in Harness/docs/CLEANUP.md.")
    }
}
