// `lisa-verify cases`: the catalogue, optionally one session or area.

import ArgumentParser
import LisaVerifyCases
import LisaVerifyKit

struct CasesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cases", abstract: "List the cases.")

    @Option(help: "Only this session (X1 … X7, LS-1 … LS-3).") var session: String?
    @Option(help: "Only this area (NEAR, APPLE, HARNESS, …).") var area: String?

    func run() throws {
        var cases = VerifyCatalogue.all
        if let session { cases = cases.filter { $0.session == session.uppercased() } }
        if let area { cases = cases.filter { $0.area == area.uppercased() } }
        for verifyCase in cases {
            let place = verifyCase.session ?? "fixture"
            print("\(verifyCase.id)\t\(place)\t\(verifyCase.executor.rawValue)\t\(verifyCase.title)")
        }
        print("\(cases.count) case\(cases.count == 1 ? "" : "s")")
    }
}
