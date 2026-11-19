// The header fields of an APNs alert request (S10): authorization, apns-id, push type, expiration, priority, topic
// and collapse ID.

import Foundation
import LisaHTTP

/// Header construction. Every field appears once (APNs rejects repeated headers with `DuplicateHeaders`).
public enum APNsRequestHeaders {
    /// APNs stores an undeliverable notification for 30 days or less (S10), so a later expiration adds nothing.
    public static let maxStorageSeconds: Int64 = 30 * 86_400

    /// The `apns-expiration` value for a notification valid until `expiresAt`: whole seconds since 1970, rounded
    /// down so APNs is never asked to hold it past Lisa's validity window, and at most 30 days ahead. Nil once the
    /// window has ended, because `0` would mean "deliver once now", not "expired".
    public static func expiration(for expiresAt: Date, now: Date) -> Int64? {
        let end = APNsEpochSeconds.of(expiresAt)
        let current = APNsEpochSeconds.of(now)
        guard end > current else { return nil }
        return min(end, current + maxStorageSeconds)
    }

    /// The headers of one alert push. `authorization` is marked sensitive, so it is never logged and never follows
    /// a redirect. `apns-collapse-id` is omitted when there is no collapse identity.
    public static func make(
        providerToken: APNsProviderToken, apnsID: String, expiration: Int64, priority: APNsPriority, topic: String,
        collapseID: String?
    ) -> [HTTPHeader] {
        var headers = [
            HTTPHeader("authorization", "bearer \(providerToken.jwt.revealed)", sensitive: true),
            HTTPHeader("apns-id", apnsID),
            HTTPHeader("apns-push-type", "alert"),
            HTTPHeader("apns-expiration", String(expiration)),
            HTTPHeader("apns-priority", priority.headerValue),
            HTTPHeader("apns-topic", topic),
        ]
        if let collapseID { headers.append(HTTPHeader("apns-collapse-id", collapseID)) }
        return headers
    }
}
