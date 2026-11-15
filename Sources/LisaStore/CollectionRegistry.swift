// The persisted collections, used to verify the schema at open time and to count records for backups.

import LisaDomain
import LisaPorts

/// Every stored entity type.
enum CollectionRegistry {
    static let all: [any StoredEntity.Type] = [
        Source.self, Evidence.self, EmailMessage.self, CalendarOccurrence.self, LisaTask.self, EventProposal.self,
        Idea.self, Capture.self, Preference.self, NewsItem.self, Plan.self, Brief.self, Reminder.self, Delivery.self,
        AuditEvent.self, DeviceRegistration.self, NotificationIntent.self, IdempotencyRecord.self,
    ]

    static var collectionNames: Set<String> { Set(all.map { $0.collectionName }) }
}
