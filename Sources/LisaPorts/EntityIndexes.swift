// Storage declarations for every domain entity: indexed fields and the unique natural keys behind deduplication.

import Foundation
import LisaDomain
import LisaTime

extension Source: StoredEntity {
    public static let indexes = [
        IndexDefinition("kind", .text), IndexDefinition("configuration_key", .text, unique: true),
        IndexDefinition("enabled", .integer),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "kind": .text(kind.rawValue), "configuration_key": .text(configurationKey),
            "enabled": .integer(enabled ? 1 : 0),
        ]
    }
}

extension Evidence: StoredEntity {
    public static let indexes = [
        IndexDefinition("source_id", .text), IndexDefinition("external_id", .text), IndexDefinition("kind", .text),
    ]

    public var indexValues: [String: IndexValue] {
        ["source_id": .text(sourceID.rawValue), "external_id": .text(externalID), "kind": .text(kind.rawValue)]
    }
}

extension EmailMessage: StoredEntity {
    public static let indexes = [
        IndexDefinition("source_id", .text), IndexDefinition("dedup_key", .text, unique: true),
        IndexDefinition("message_id", .text), IndexDefinition("received_at", .integer),
        IndexDefinition("extraction", .text),
    ]

    /// The per-source natural key: the same message from the same source is stored once (MAIL-02).
    public static func dedupKey(sourceID: SourceID, messageKey: String) -> String {
        "\(sourceID.rawValue)|\(messageKey)"
    }

    public var indexValues: [String: IndexValue] {
        [
            "source_id": .text(sourceID.rawValue),
            "dedup_key": .text(EmailMessage.dedupKey(sourceID: sourceID, messageKey: messageKey)),
            "message_id": messageID.map(IndexValue.text) ?? .null, "received_at": .instant(receivedAt),
            "extraction": .text(extraction.rawValue),
        ]
    }
}

extension CalendarOccurrence: StoredEntity {
    public static let indexes = [
        IndexDefinition("source_id", .text), IndexDefinition("natural_key", .text, unique: true),
        IndexDefinition("uid", .text),
        IndexDefinition("start_at", .integer), IndexDefinition("end_at", .integer), IndexDefinition("status", .text),
    ]

    public static func naturalKey(sourceID: SourceID, uid: String, occurrenceKey: String) -> String {
        "\(sourceID.rawValue)|\(uid)|\(occurrenceKey)"
    }

    /// Start and end for range queries. All-day occurrences use UTC midnights; callers widen ranges by a day.
    public var indexRange: (Date, Date) {
        switch timing {
        case .timed(let start, let end, _, _): (start, end)
        case .allDay(let first, let endExclusive):
            (
                Date(timeIntervalSince1970: TimeInterval(first.daysSinceEpoch) * 86_400),
                Date(timeIntervalSince1970: TimeInterval(endExclusive.daysSinceEpoch) * 86_400)
            )
        }
    }

    public var indexValues: [String: IndexValue] {
        let (start, end) = indexRange
        return [
            "source_id": .text(sourceID.rawValue),
            "natural_key": .text(
                CalendarOccurrence.naturalKey(sourceID: sourceID, uid: uid, occurrenceKey: occurrenceKey)),
            "uid": .text(uid), "start_at": .instant(start), "end_at": .instant(end), "status": .text(status.rawValue),
        ]
    }
}

extension LisaTask: StoredEntity {
    public static let indexes = [
        IndexDefinition("status", .text), IndexDefinition("confirmation", .text),
        IndexDefinition("deadline_at", .integer),
        IndexDefinition("origin", .text),
    ]

    public var indexValues: [String: IndexValue] {
        let deadlineAt: Date? =
            switch deadline {
            case .at(let instant, _): instant
            case .onDate(let date): Date(timeIntervalSince1970: TimeInterval(date.daysSinceEpoch) * 86_400)
            case nil: nil
            }
        return [
            "status": .text(status.rawValue), "confirmation": .text(confirmation.rawValue),
            "deadline_at": .instant(deadlineAt),
            "origin": .text(origin.rawValue),
        ]
    }
}

extension EventProposal: StoredEntity {
    public static let indexes = [IndexDefinition("match_state", .text), IndexDefinition("created_at", .integer)]

    public var indexValues: [String: IndexValue] {
        ["match_state": .text(matchState.name), "created_at": .instant(createdAt)]
    }
}

extension Idea: StoredEntity {
    public static let indexes = [IndexDefinition("lifecycle", .text), IndexDefinition("created_at", .integer)]

    public var indexValues: [String: IndexValue] {
        ["lifecycle": .text(lifecycle.rawValue), "created_at": .instant(createdAt)]
    }
}

extension Capture: StoredEntity {
    public static let indexes = [
        IndexDefinition("request_id", .text, unique: true), IndexDefinition("captured_at", .integer),
        IndexDefinition("processing", .text),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "request_id": requestID.map(IndexValue.text) ?? .null, "captured_at": .instant(capturedAt),
            "processing": .text(processing.rawValue),
        ]
    }
}

extension Preference: StoredEntity {
    public static let indexes = [IndexDefinition("key", .text, unique: true)]

    public var indexValues: [String: IndexValue] { ["key": .text(key.rawValue)] }
}

extension NewsItem: StoredEntity {
    public static let indexes = [
        IndexDefinition("source_id", .text), IndexDefinition("dedup_key", .text, unique: true),
        IndexDefinition("published_at", .integer), IndexDefinition("retrieved_at", .integer),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "source_id": .text(sourceID.rawValue), "dedup_key": .text(dedupKey), "published_at": .instant(publishedAt),
            "retrieved_at": .instant(retrievedAt),
        ]
    }
}

extension Plan: StoredEntity {
    public static let indexes = [
        IndexDefinition("natural_key", .text, unique: true), IndexDefinition("local_date", .text),
    ]

    public var indexValues: [String: IndexValue] {
        ["natural_key": .text(Plan.key(date: localDate, zone: zone)), "local_date": .text(localDate.iso)]
    }
}

extension Brief: StoredEntity {
    public static let indexes = [
        IndexDefinition("natural_key", .text, unique: true), IndexDefinition("local_date", .text),
        IndexDefinition("state", .text),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "natural_key": .text(Brief.key(date: localDate, zone: zone)), "local_date": .text(localDate.iso),
            "state": .text(state.rawValue),
        ]
    }
}

extension Reminder: StoredEntity {
    public static let indexes = [
        IndexDefinition("occurrence_key", .text, unique: true), IndexDefinition("state", .text),
        IndexDefinition("due_at", .integer),
        IndexDefinition("subject_key", .text), IndexDefinition("rule", .text),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "occurrence_key": .text(occurrenceKey), "state": .text(state.name), "due_at": .instant(dueAt),
            "subject_key": .text(subject.key), "rule": .text(rule.rawValue),
        ]
    }
}

extension Delivery: StoredEntity {
    public static let indexes = [
        IndexDefinition("idempotency_key", .text, unique: true), IndexDefinition("state", .text),
        IndexDefinition("next_attempt_at", .integer), IndexDefinition("lease_expires_at", .integer),
        IndexDefinition("channel", .text), IndexDefinition("recipient_key", .text),
        IndexDefinition("payload_key", .text),
    ]

    /// A key for the payload, such as `notification:<id>`.
    public var payloadKey: String {
        switch payload {
        case .reminder(let id): "reminder:\(id.rawValue)"
        case .brief(let id): "brief:\(id.rawValue)"
        case .notification(let id): "notification:\(id.rawValue)"
        }
    }

    public var indexValues: [String: IndexValue] {
        [
            "idempotency_key": .text(idempotencyKey), "state": .text(state.rawValue),
            "next_attempt_at": .instant(nextAttemptAt),
            "lease_expires_at": .instant(leaseExpiresAt), "channel": .text(channel.rawValue),
            "recipient_key": .text(recipient.description), "payload_key": .text(payloadKey),
        ]
    }
}

extension AuditEvent: StoredEntity {
    public static let indexes = [IndexDefinition("at", .integer), IndexDefinition("action", .text)]

    public var indexValues: [String: IndexValue] { ["at": .instant(at), "action": .text(action)] }
}

extension DeviceRegistration: StoredEntity {
    public static let indexes = [
        IndexDefinition("installation_id", .text, unique: true),
        IndexDefinition("credential_verifier", .text, unique: true),
        IndexDefinition("state", .text),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "installation_id": .text(installationID), "credential_verifier": .text(credentialVerifier),
            "state": .text(state.rawValue),
        ]
    }
}

extension NotificationIntent: StoredEntity {
    public static let indexes = [
        IndexDefinition("occurrence_key", .text, unique: true), IndexDefinition("subject_key", .text),
        IndexDefinition("category", .text), IndexDefinition("state", .text), IndexDefinition("created_at", .integer),
    ]

    public var indexValues: [String: IndexValue] {
        [
            "occurrence_key": .text(occurrenceKey), "subject_key": .text(subject.key),
            "category": .text(category.rawValue),
            "state": .text(state.rawValue), "created_at": .instant(createdAt),
        ]
    }
}
