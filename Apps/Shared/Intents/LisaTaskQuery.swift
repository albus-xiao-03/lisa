// How Siri and Shortcuts find Lisa tasks: by stable identifier, by spoken name with every match kept, and as
// suggestions.

import AppIntents
import Foundation
import LisaPresentation

/// Finds tasks for the App Intents through the app's shared client services (SIRI-01). A spoken name returns every
/// completable task that matches (`TitleMatcher`), an exact title first, so the system asks which one was meant when
/// several match. While the host is unreachable, the tasks cached on this device are offered.
struct LisaTaskQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [LisaTaskEntity.ID]) async throws -> [LisaTaskEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.tasks(withIDs: identifiers).map(LisaTaskEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LisaTaskEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.tasks(matching: string).map(LisaTaskEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [LisaTaskEntity] {
        let actions = try SiriFailure.requireActions()
        do throws(SiriLookupError) {
            return try await actions.completableTasks().map(LisaTaskEntity.init(item:))
        } catch {
            throw SiriFailure(message: error.message)
        }
    }
}
