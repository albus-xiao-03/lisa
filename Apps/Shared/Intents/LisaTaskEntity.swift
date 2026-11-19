// A Lisa task as an App Intents entity: identified by the host's stable task identifier.

import AppIntents
import Foundation
import LisaPresentation

/// A task Siri and Shortcuts can choose (SIRI-01). Its identifier is the host's task identifier, so a saved shortcut
/// keeps referring to the same task; its title and detail, such as the deadline, tell similar tasks apart when Siri
/// asks which one was meant.
struct LisaTaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Task") }

    static var defaultQuery: LisaTaskQuery { LisaTaskQuery() }

    /// The task as last read, with the revision an action expects.
    let item: SiriItem

    var id: String { item.id }

    var displayRepresentation: DisplayRepresentation {
        guard let detail = item.detail else { return DisplayRepresentation(title: "\(item.title)") }
        return DisplayRepresentation(title: "\(item.title)", subtitle: "\(detail)")
    }
}
