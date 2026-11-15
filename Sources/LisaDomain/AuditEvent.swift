// Audit records of attempted actions and their outcomes, without secrets or unnecessary private content.

import Foundation

/// The outcome of an audited action.
public enum AuditOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case denied
    case skipped
    case simulated
}

/// One audited action.
public struct AuditEvent: Entity {
    public static let collectionName = "audit"
    public let id: AuditID
    public var revision: Revision
    public var updatedAt: Date
    public var action: String
    public var actor: Principal
    public var at: Date
    public var affected: [String]
    public var outcome: AuditOutcome
    /// A redacted description; never message bodies, credentials or private URLs.
    public var detail: String

    public init(
        id: AuditID = .random(), action: String, actor: Principal, at: Date, affected: [String],
        outcome: AuditOutcome, detail: String
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = at
        self.action = action
        self.actor = actor
        self.at = at
        self.affected = affected
        self.outcome = outcome
        self.detail = detail
    }
}
