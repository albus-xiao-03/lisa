// How Siri and Shortcuts find Lisa reminders: by stable identifier, by spoken name with every match kept, and as
// suggestions.

import AppIntents
import Foundation
import LisaPresentation

/// Finds reminders that can be snoozed for the App Intents through the app's shared client services (SIRI-01). A
/// spoken name returns every matching reminder (`TitleMatcher`), an exact title first, so the system asks which one
/// was meant when several match. Reminders are not cached on the device, so listing them needs the host.
struct LisaReminderQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [LisaReminderEntity.ID]) async throws -> [LisaReminderEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.reminders(withIDs: identifiers).map(LisaReminderEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LisaReminderEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.reminders(matching: string).map(LisaReminderEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [LisaReminderEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.snoozableReminders().map(LisaReminderEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }
}
