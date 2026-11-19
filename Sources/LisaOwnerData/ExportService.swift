// Versioned JSON export of the owner's data (DATA-05), without credentials, verifiers or push tokens.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// A paired device as exported: no credential verifier and no push token.
public struct ExportedDevice: Codable, Sendable {
    public var id: DeviceID
    public var name: String
    public var deviceClass: DeviceClass
    public var state: DeviceState
    public var pairedAt: Date
    public var authorization: NotificationAuthorization
    public var preferences: DeviceNotificationPreferences
    public var hasActivePushToken: Bool

    init(_ device: DeviceRegistration) {
        id = device.id
        name = device.name
        deviceClass = device.deviceClass
        state = device.state
        pairedAt = device.pairedAt
        authorization = device.authorization
        preferences = device.preferences
        hasActivePushToken = device.pushToken?.state == .active
    }
}

/// Exports every owner record as one JSON document.
public final class ExportService: Sendable {
    /// The export format identifier and version; a reader rejects versions it does not know.
    public static let format = "lisa-export"
    public static let formatVersion = 1

    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    /// The export document. `schemaVersion` is the database schema the records were read from.
    public func export(schemaVersion: Int, applicationVersion: String, by principal: Principal) throws -> Data {
        guard principal.mayChangeConsequentialSettings else {
            throw DomainError.notPermitted("only the owner on the host can export data")
        }
        let now = clock.now()
        var collections: [String: Any] = [:]
        try store.read { tx in
            collections[Source.collectionName] = try Self.json(tx.find(Source.self, .all))
            collections[Evidence.collectionName] = try Self.json(tx.find(Evidence.self, .all))
            collections[EmailMessage.collectionName] = try Self.json(tx.find(EmailMessage.self, .all))
            collections[CalendarOccurrence.collectionName] = try Self.json(tx.find(CalendarOccurrence.self, .all))
            collections[LisaTask.collectionName] = try Self.json(tx.find(LisaTask.self, .all))
            collections[EventProposal.collectionName] = try Self.json(tx.find(EventProposal.self, .all))
            collections[Idea.collectionName] = try Self.json(tx.find(Idea.self, .all))
            collections[Capture.collectionName] = try Self.json(tx.find(Capture.self, .all))
            collections[Preference.collectionName] = try Self.json(tx.find(Preference.self, .all))
            collections[NewsItem.collectionName] = try Self.json(tx.find(NewsItem.self, .all))
            collections[Plan.collectionName] = try Self.json(tx.find(Plan.self, .all))
            collections[Brief.collectionName] = try Self.json(tx.find(Brief.self, .all))
            collections[Reminder.collectionName] = try Self.json(tx.find(Reminder.self, .all))
            collections[NotificationIntent.collectionName] = try Self.json(tx.find(NotificationIntent.self, .all))
            collections[Delivery.collectionName] = try Self.json(tx.find(Delivery.self, .all))
            collections[AuditEvent.collectionName] = try Self.json(tx.find(AuditEvent.self, .all))
            collections[DeviceRegistration.collectionName] = try Self.json(
                tx.find(DeviceRegistration.self, .all).map(ExportedDevice.init))
        }
        let document: [String: Any] = [
            "format": Self.format, "formatVersion": Self.formatVersion, "schemaVersion": schemaVersion,
            "applicationVersion": applicationVersion, "exportedAt": now.millisecondsSince1970,
            "collections": collections,
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
        try store.write { tx in
            try tx.insert(
                AuditEvent(
                    action: "data.exported", actor: principal, at: now, affected: [], outcome: .succeeded,
                    detail: "\(data.count) bytes"))
        }
        logger.notice("data exported", ["bytes": .count(data.count)])
        return data
    }

    static func json<T: Encodable>(_ values: [T]) throws -> Any {
        try JSONSerialization.jsonObject(with: DomainJSON.encoder().encode(values))
    }
}
