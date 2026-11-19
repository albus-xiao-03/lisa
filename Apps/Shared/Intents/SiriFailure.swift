// A reason Siri or Shortcuts shows when an App Intent cannot list Lisa's tasks or reminders, or Lisa is not set up.

import AppIntents
import Foundation
import LisaPresentation

/// An error an App Intent's query throws, with a sentence the system shows or speaks. It never contains the owner's
/// content.
struct SiriFailure: Error, CustomLocalizedStringResourceConvertible {
    /// The sentence shown or spoken.
    let message: String

    var localizedStringResource: LocalizedStringResource { "\(message)" }

    /// The actions of the app's shared client services, or the "not set up" failure.
    @MainActor
    static func requireActions() throws -> SiriActions {
        guard let actions = LisaClientEnvironment.shared.intentActions() else {
            throw SiriFailure(message: SiriReply.notSetUp.dialog)
        }
        return actions
    }
}
