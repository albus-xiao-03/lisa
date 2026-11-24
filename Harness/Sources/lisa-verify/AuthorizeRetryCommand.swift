// `lisa-verify authorize-retry <action ID>` (plan §10.8 "The action ledger" step 4): shows the evidence of an
// ambiguous action and asks the owner to type "may duplicate <action ID>". Only that phrase authorizes exactly one
// further attempt, recorded as `<action ID>.r2`; the next `resume` performs it. Nothing else ever sends again.

import ArgumentParser
import LisaVerifyKit

struct AuthorizeRetryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "authorize-retry", abstract: "Authorize one further attempt of an ambiguous action.")

    @Argument(help: "The action ID, OVA-<run-id>-<case>-<n>.") var actionID: String
    @OptionGroup var storeOptions: StoreOptions

    func run() throws {
        let run = try Self.runID(of: actionID)
        let store = storeOptions.store
        let ledger = try VerifyActionLedger(path: store.ledgerPath(of: run))
        guard let record = try ledger.record(actionID) else {
            throw VerifyError.retryNotAuthorized("no action \(actionID)")
        }
        print("\(record.actionID): \(record.kind.rawValue) to \(record.targetAlias), state \(record.state.rawValue)")
        print("Evidence: \(record.outcome ?? "none")")
        print("A further attempt may cause a duplicate. To authorize exactly one, type: may duplicate \(actionID)")
        let typed = readLine(strippingNewline: true) ?? ""
        let retry = try ledger.authorizeRetry(actionID, typedPhrase: typed)
        print("Authorized \(retry.actionID); run `lisa-verify resume \(run)` to perform it.")
    }

    /// The run ID inside `OVA-<run-id>-<case>-<n>`.
    static func runID(of actionID: String) throws(VerifyError) -> VerifyRunID {
        guard actionID.hasPrefix("OVA-"), actionID.count > 31 else {
            throw .invalidInput("not an action ID: \(actionID)")
        }
        let start = actionID.index(actionID.startIndex, offsetBy: 4)
        let end = actionID.index(start, offsetBy: 27)
        return try VerifyRunID(String(actionID[start..<end]))
    }
}
