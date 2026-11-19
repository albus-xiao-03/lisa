// The request ledger (API-03): a retried request ID replays the original response instead of repeating a mutation.

import Foundation
import LisaDomain
import LisaPorts

/// What the ledger knows about a request ID.
public enum LedgerLookup: Hashable, Sendable {
    case unknown
    /// The same request was already answered; return this response again.
    case replay(statusCode: Int, body: Data)
    /// The request ID was used for a different request.
    case mismatch
}

extension LisaApplication {
    /// Looks up a request by its scoped key (principal and request ID) and request fingerprint.
    public func lookupRequest(scopedKey: String, fingerprint: String) throws -> LedgerLookup {
        let now = clock.now()
        guard
            let record = try store.read({
                try $0.first(IdempotencyRecord.self, RecordQuery.all.filter("scoped_key", equals: scopedKey))
            }), record.expiresAt > now
        else { return .unknown }
        return record.requestFingerprint == fingerprint
            ? .replay(statusCode: record.statusCode, body: record.responseBody) : .mismatch
    }

    /// Records the response to a request for `retentionDays`.
    public func recordRequest(scopedKey: String, fingerprint: String, statusCode: Int, body: Data, retentionDays: Int)
        throws
    {
        let now = clock.now()
        let expiry = now.addingTimeInterval(Double(max(1, retentionDays)) * 86_400)
        try store.write { tx in
            if var existing = try tx.first(
                IdempotencyRecord.self, RecordQuery.all.filter("scoped_key", equals: scopedKey))
            {
                existing.requestFingerprint = fingerprint
                existing.statusCode = statusCode
                existing.responseBody = body
                existing.expiresAt = expiry
                existing.updatedAt = now
                try tx.update(existing)
            } else {
                try tx.insert(
                    IdempotencyRecord(
                        scopedKey: scopedKey, requestFingerprint: fingerprint, statusCode: statusCode,
                        responseBody: body,
                        expiresAt: expiry, now: now))
            }
        }
    }

    /// Deletes expired ledger entries.
    @discardableResult
    public func pruneRequestLedger() throws -> Int {
        let now = clock.now()
        return try store.write { tx in
            let expired = try tx.find(
                IdempotencyRecord.self, RecordQuery.all.filter("expires_at", .lessOrEqual, .instant(now)))
            for record in expired { try tx.delete(IdempotencyRecord.self, id: record.id) }
            return expired.count
        }
    }
}
