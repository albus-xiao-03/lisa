// "Get today's brief" for Siri and Shortcuts (SIRI-01, SIRI-02): the prepared brief as text to speak, saying how old
// it is when it is a saved copy.

import AppIntents
import Foundation
import LisaPresentation

/// Gets today's brief as text and says it (SIRI-01). The text is also the intent's result, so a personal automation
/// in Shortcuts can pass it to Speak Text (SIRI-02); the app never installs such an automation itself.
///
/// While the host is unreachable, the brief saved on this device is used and starts with its day and age; with no
/// brief, the reply says why. It runs in the background in the app's process, also while the device is locked.
struct GetBriefIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Today's Brief" }

    static var description: IntentDescription {
        IntentDescription(
            "Gets today's brief from Lisa as text to speak. A copy saved on this device says how old it is.")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.brief() ?? .notSetUp
        return .result(value: reply.dialog, dialog: "\(reply.dialog)")
    }
}
