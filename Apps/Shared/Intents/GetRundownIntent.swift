// "Get today's rundown" for Siri and Shortcuts (SIRI-01): today's planned blocks as text to speak, saying how old they
// are when they are a saved copy.

import AppIntents
import Foundation
import LisaPresentation

/// Gets today's rundown, the planned blocks with their start times, as text and says it (SIRI-01). While the host is
/// unreachable, the rundown saved on this device is used and starts with its day and age; with none, the reply says
/// why.
struct GetRundownIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Today's Rundown" }

    static var description: IntentDescription {
        IntentDescription(
            "Gets today's plan from Lisa as text to speak. A copy saved on this device says how old it is.")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.rundown() ?? .notSetUp
        return .result(value: reply.dialog, dialog: "\(reply.dialog)")
    }
}
