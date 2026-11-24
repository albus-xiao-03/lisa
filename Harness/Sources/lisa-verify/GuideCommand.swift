// `lisa-verify guide <case>` (plan §10.8): each step no test can drive, with its expected outcome, plus the case's
// environment, prerequisites, evidence and gate.

import ArgumentParser
import LisaVerifyCases
import LisaVerifyKit

struct GuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "guide", abstract: "Show a case's guided steps.")

    @Argument(help: "The case ID, for example OV-NEAR-MI-01.") var caseID: String

    func run() throws {
        let verifyCase = try VerifyCatalogue.find(try VerifyCaseID(caseID))
        print("\(verifyCase.id) — \(verifyCase.title)")
        print(
            "Executor: \(verifyCase.executor.rawValue); session: \(verifyCase.session ?? "fixture"); gate: \(verifyCase.gate)"
        )
        print("Interface: \(verifyCase.interface)")
        print("Environment: \(verifyCase.environment)")
        print("Required result level: \(verifyCase.requiredResultLevel.rawValue)")
        print("Prerequisites:")
        for item in verifyCase.prerequisites { print("  - \(item)") }
        print("Required evidence: \(verifyCase.requiredEvidence.joined(separator: "; "))")
        print("Expected outcome: \(verifyCase.expectedOutcome)")
        if verifyCase.paired { print("Paired: each device records \(verifyCase.id)@sender or @receiver.") }
        print("Steps:")
        for (index, step) in verifyCase.manualSteps.enumerated() { print("  \(index + 1). \(step)") }
    }
}
