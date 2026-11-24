// `lisa-verify run` (plan §10.8 "Commands"): a fixture run executes the fixture cases here and now, with the
// controlled servers, and records a result per case; a device run is created for the owner's session and lists each
// case's guide. Live cases join the catalogue with LS-1 to LS-3 (M7, M8).

import ArgumentParser
import Foundation
import LisaVerifyCases
import LisaVerifyKit

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Start a run.")

    @Option(name: .customLong("case"), help: "A case to run (repeatable).") var cases: [String] = []
    @Option(help: "Only this area.") var area: String?
    @Option(help: "Only this session.") var session: String?
    @Option(help: "fixture | device | live") var mode: String = "fixture"
    @OptionGroup var storeOptions: StoreOptions

    func run() async throws {
        guard let mode = VerifyMode(rawValue: mode) else {
            throw VerifyError.invalidInput("--mode: fixture, device or live")
        }
        var selection = VerifyCatalogue.all.filter { $0.modes.contains(mode) }
        if !cases.isEmpty {
            let wanted = Set(try cases.map { try VerifyCaseID($0) })
            selection = selection.filter { wanted.contains($0.id) }
            guard selection.count == wanted.count else {
                throw VerifyError.invalidInput("some --case values aren't \(mode.rawValue) cases in the catalogue")
            }
        }
        if let area { selection = selection.filter { $0.area == area.uppercased() } }
        if let session { selection = selection.filter { $0.session == session.uppercased() } }
        guard !selection.isEmpty else { throw VerifyError.invalidInput("no \(mode.rawValue) case selected") }
        let store = storeOptions.store
        var run = VerifyRun(
            id: VerifyRunID.generate(), mode: mode, createdAt: VerifyClock.wallClock(), commit: HarnessInfo.commit(),
            harnessVersion: HarnessInfo.version, selection: selection.map(\.id))
        try store.create(run)
        print("Run \(run.id) (\(mode.rawValue)), \(selection.count) case(s)")
        guard mode == .fixture else {
            for verifyCase in selection {
                run.caseStates[verifyCase.id.text] = .waitingForOwner
                print("  \(verifyCase.id) — lisa-verify guide \(verifyCase.id)")
            }
            try store.save(run)
            return
        }
        var failed = 0
        for verifyCase in selection {
            let record = try await FixtureCaseRunner.execute(
                verifyCase, run: &run, store: store, home: store.home.path, attempt: 0)
            if record.status != .pass { failed += 1 }
        }
        print("Report: lisa-verify report \(run.id)")
        if failed > 0 { throw ExitCode(1) }
    }
}
