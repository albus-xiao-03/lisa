// "Save for a future brief" for Siri and Shortcuts (SIRI-01, NEWS-04): supplied text or a link, saved in Lisa or kept
// on this device while the host is unreachable.

import AppIntents
import Foundation
import LisaPresentation

/// Saves supplied text or a URL for a future brief (SIRI-01). A lone web address is saved as a link, an Apple News
/// link as content shared from Apple News (NEWS-04); anything else as text. Nothing is fetched here. The reply says
/// whether it was saved on the host, kept on this device to be sent later, or not saved and why.
struct SaveForBriefIntent: AppIntent {
    static var title: LocalizedStringResource { "Save for a Future Brief" }

    static var description: IntentDescription {
        IntentDescription(
            "Saves text or a link for a future brief. Offline, it waits on this device and is sent later.")
    }

    @Parameter(title: "Text or Link", requestValueDialog: IntentDialog("What should Lisa save?"))
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$content) for a future brief")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.saveForBrief(content) ?? .notSetUp
        return .result(dialog: "\(reply.dialog)")
    }
}
