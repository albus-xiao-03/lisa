// A Lisa reminder as an App Intents entity: identified by the host's stable reminder identifier.

import AppIntents
import Foundation
import LisaPresentation

/// A reminder Siri and Shortcuts can choose (SIRI-01). Its identifier is the host's reminder identifier; its title and
/// when it is due tell similar reminders apart when Siri asks which one was meant.
struct LisaReminderEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Reminder") }

    static var defaultQuery: LisaReminderQuery { LisaReminderQuery() }

    /// The reminder as last read, with the revision an action expects.
    let item: SiriItem

    var id: String { item.id }

    var displayRepresentation: DisplayRepresentation {
        guard let detail = item.detail else { return DisplayRepresentation(title: "\(item.title)") }
        return DisplayRepresentation(title: "\(item.title)", subtitle: "\(detail)")
    }
}
