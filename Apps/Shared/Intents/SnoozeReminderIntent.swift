// "Snooze a reminder" for Siri and Shortcuts (SIRI-01): the chosen reminder, by its stable identifier, for the host's
// snooze duration.

import AppIntents
import Foundation
import LisaPresentation

/// Snoozes a selected reminder for the snooze duration configured on the host, which computes the next reminder
/// (SIRI-01, plan §6.5). Siri asks which reminder, offering every match of a spoken name. The action expects the
/// revision last read and goes through the durable queue; the reply says done (with the new time), queued until the
/// host can be reached, changed on the host, unavailable, or failed.
struct SnoozeReminderIntent: AppIntent {
    static var title: LocalizedStringResource { "Snooze a Reminder" }

    static var description: IntentDescription {
        IntentDescription("Snoozes one of your Lisa reminders for the snooze time set on your Lisa host.")
    }

    @Parameter(title: "Reminder", requestValueDialog: IntentDialog("Which reminder?"))
    var reminder: LisaReminderEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Snooze \(\.$reminder)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await LisaClientEnvironment.shared.intentActions()?.snooze(reminder.item) ?? .notSetUp
        return .result(dialog: "\(reply.dialog)")
    }
}
