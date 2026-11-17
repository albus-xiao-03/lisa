// "Capture an idea" for Siri and Shortcuts (SIRI-01): saved in Lisa, or kept on this device while the host is
// unreachable.

import AppIntents
import Foundation
import LisaPresentation

/// Captures an idea (SIRI-01, IDEA-01). It is queued durably with a stable request ID, then sent; the reply says
/// whether it was saved on the host, kept on this device to be sent later, or not saved and why.
struct CaptureIdeaIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture an Idea" }

    static var description: IntentDescription {
        IntentDescription(
            "Saves an idea in Lisa. While your Lisa host can't be reached, it is kept on this device and sent later.")
    }

    @Parameter(title: "Idea", requestValueDialog: IntentDialog("What's the idea?"))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) in Lisa")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.captureIdea(text) ?? .notSetUp
        return .result(dialog: "\(reply.dialog)")
    }
}
