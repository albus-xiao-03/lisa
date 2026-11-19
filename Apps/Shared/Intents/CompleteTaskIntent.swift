// "Mark a task complete" for Siri and Shortcuts (SIRI-01): the chosen task, by its stable identifier, after the device
// is unlocked.

import AppIntents
import Foundation
import LisaPresentation

/// Marks a selected task complete (SIRI-01). Siri asks which task, offering every match of a spoken name. The change
/// expects the revision last read and goes through the durable queue; the reply says done, queued until the host can
/// be reached, changed on the host (a conflict to review in the app), unavailable, or failed. It requires the device
/// to be unlocked, like the notification action.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Mark a Task Complete" }

    static var description: IntentDescription {
        IntentDescription("Marks one of your Lisa tasks complete.")
    }

    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Task", requestValueDialog: IntentDialog("Which task?"))
    var task: LisaTaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$task) complete")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.complete(task.item) ?? .notSetUp
        return .result(dialog: "\(reply.dialog)")
    }
}
