// Persisted idempotency records for mutating API requests (API-03): one response per principal and request key.

import Foundation
import LisaDomain

public enum IdempotencyTag: EntityTag {}
public typealias IdempotencyRecordID = EntityID<IdempotencyTag>

/// The stored outcome of a mutating request, replayed when the same request identity is retried.
public struct IdempotencyRecord: StoredEntity {
    public static let collectionName = "idempotency"
    public let id: IdempotencyRecordID
    public var revision: Revision
    public var updatedAt: Date
    /// `<principal>|<client request id>`.
    public var scopedKey: String
    /// A fingerprint of the request; the same key with a different request is a conflict, not a replay.
    public var requestFingerprint: String
    public var statusCode: Int
    public var responseBody: Data
    public var expiresAt: Date

    public init(
        scopedKey: String, requestFingerprint: String, statusCode: Int, responseBody: Data, expiresAt: Date, now: Date
    ) {
        self.id = .random()
        self.revision = .initial
        self.updatedAt = now
        self.scopedKey = scopedKey
        self.requestFingerprint = requestFingerprint
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.expiresAt = expiresAt
    }

    public static let indexes = [
        IndexDefinition("scoped_key", .text, unique: true), IndexDefinition("expires_at", .integer),
    ]

    public var indexValues: [String: IndexValue] {
        ["scoped_key": .text(scopedKey), "expires_at": .instant(expiresAt)]
    }
}
