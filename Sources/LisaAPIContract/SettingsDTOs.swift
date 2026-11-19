// Preference, source-status and health DTOs (API-02 preference, source and health routes).

import Foundation

/// A preference value: exactly one of the four forms.
public enum PreferenceValueDTO: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case list([String])

    private enum CodingKeys: String, CodingKey {
        case text, number, flag, list
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "a preference value has exactly one of text, number, flag or list"))
        }
        switch key {
        case .text: self = .text(try container.decode(String.self, forKey: .text))
        case .number: self = .number(try container.decode(Double.self, forKey: .number))
        case .flag: self = .flag(try container.decode(Bool.self, forKey: .flag))
        case .list: self = .list(try container.decode([String].self, forKey: .list))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value): try container.encode(value, forKey: .text)
        case .number(let value): try container.encode(value, forKey: .number)
        case .flag(let value): try container.encode(value, forKey: .flag)
        case .list(let value): try container.encode(value, forKey: .list)
        }
    }
}

/// A stored preference.
public struct PreferenceDTO: Codable, Hashable, Sendable {
    public var key: String
    public var value: PreferenceValueDTO
    /// `explicit` or `inferred`.
    public var origin: String
    public var confirmed: Bool
    /// Whether the value currently takes effect.
    public var effective: Bool
    /// Consequential keys can be changed only by the owner on the host.
    public var consequential: Bool
    public var revision: Int64
    public var updatedAt: Date

    public init(
        key: String, value: PreferenceValueDTO, origin: String, confirmed: Bool, effective: Bool, consequential: Bool,
        revision: Int64, updatedAt: Date
    ) {
        self.key = key
        self.value = value
        self.origin = origin
        self.confirmed = confirmed
        self.effective = effective
        self.consequential = consequential
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

/// One change in `PATCH /v1/preferences`.
public struct PreferenceChange: Codable, Hashable, Sendable {
    public var key: String
    /// The new value; omit it to delete the preference.
    public var value: PreferenceValueDTO?
    /// Confirms an inferred preference without changing it.
    public var confirm: Bool?
    public var expectedRevision: Int64?

    public init(key: String, value: PreferenceValueDTO? = nil, confirm: Bool? = nil, expectedRevision: Int64? = nil) {
        self.key = key
        self.value = value
        self.confirm = confirm
        self.expectedRevision = expectedRevision
    }
}

/// `PATCH /v1/preferences`. Changes are applied in order; the first refused change stops the request.
public struct PreferencesPatchRequest: Codable, Hashable, Sendable {
    public var changes: [PreferenceChange]

    public init(changes: [PreferenceChange]) {
        self.changes = changes
    }
}

/// The health and freshness of one source.
public struct SourceStatusDTO: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var enabled: Bool
    /// `fresh`, `stale`, `neverSynchronized` or `disabled`.
    public var freshness: String
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var failing: Bool
    public var failureClass: String?
    public var failureSummary: String?
    public var retryAfter: Date?
    public var notes: [String]

    public init(
        id: String, name: String, kind: String, enabled: Bool, freshness: String, lastAttemptAt: Date?,
        lastSuccessAt: Date?, failing: Bool, failureClass: String?, failureSummary: String?, retryAfter: Date?,
        notes: [String]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.freshness = freshness
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.failing = failing
        self.failureClass = failureClass
        self.failureSummary = failureSummary
        self.retryAfter = retryAfter
        self.notes = notes
    }
}

/// Delivery counts by state, for health.
public struct OutboxSummaryDTO: Codable, Hashable, Sendable {
    public var pending: Int
    public var inProgress: Int
    public var outcomeUnknown: Int
    public var failed: Int
    public var capturedDryRun: Int

    public init(pending: Int, inProgress: Int, outcomeUnknown: Int, failed: Int, capturedDryRun: Int) {
        self.pending = pending
        self.inProgress = inProgress
        self.outcomeUnknown = outcomeUnknown
        self.failed = failed
        self.capturedDryRun = capturedDryRun
    }
}

/// `GET /v1/health`. Never contains secrets or raw private content.
public struct HealthDTO: Codable, Hashable, Sendable {
    /// `ok`, `degraded` or `failing`.
    public var status: String
    public var apiVersion: String
    public var applicationVersion: String
    public var schemaVersion: Int
    public var startedAt: Date
    public var lastCycleAt: Date?
    public var lastCycleProblem: String?
    /// `dryRun` or `live` per channel: `email`, `call`, `push`, `localNotification`.
    public var deliveryModes: [String: String]
    public var outbox: OutboxSummaryDTO
    public var sources: [SourceStatusDTO]
    /// Paired devices that cannot currently receive notifications, with the reason.
    public var deviceWarnings: [String]
    public var warnings: [String]
    /// The model configuration; absent from hosts that do not report it, which decode as `nil`.
    public var model: ModelStatusDTO?

    public init(
        status: String, apiVersion: String, applicationVersion: String, schemaVersion: Int, startedAt: Date,
        lastCycleAt: Date?, lastCycleProblem: String?, deliveryModes: [String: String], outbox: OutboxSummaryDTO,
        sources: [SourceStatusDTO], deviceWarnings: [String], warnings: [String], model: ModelStatusDTO? = nil
    ) {
        self.status = status
        self.apiVersion = apiVersion
        self.applicationVersion = applicationVersion
        self.schemaVersion = schemaVersion
        self.startedAt = startedAt
        self.lastCycleAt = lastCycleAt
        self.lastCycleProblem = lastCycleProblem
        self.deliveryModes = deliveryModes
        self.outbox = outbox
        self.sources = sources
        self.deviceWarnings = deviceWarnings
        self.warnings = warnings
        self.model = model
    }
}
