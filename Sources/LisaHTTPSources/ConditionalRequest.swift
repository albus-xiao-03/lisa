// Builds the GET for one document fetch: conditional headers from a matching and recent cursor, identity content
// coding, and the size, time, redirect and public-address bounds.

import Foundation
import LisaHTTP

/// The bounds one fetch runs under, already reconciled with the synchronization pass's limits.
package struct FetchBounds: Hashable, Sendable {
    /// The largest response body accepted.
    package var maxBytes: Int
    /// Each exchange (one redirect hop), including connection setup.
    package var timeoutSeconds: Double
    package var connectTimeoutSeconds: Double
    /// The whole fetch, redirects included.
    package var deadlineSeconds: Double
    package var maxRedirects: Int
    /// Validators older than this are not sent, so the next fetch downloads the document in full.
    package var validatorLifetimeSeconds: Double

    package init(
        maxBytes: Int, timeoutSeconds: Double, connectTimeoutSeconds: Double, deadlineSeconds: Double,
        maxRedirects: Int,
        validatorLifetimeSeconds: Double
    ) {
        self.maxBytes = maxBytes
        self.timeoutSeconds = timeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.deadlineSeconds = deadlineSeconds
        self.maxRedirects = maxRedirects
        self.validatorLifetimeSeconds = validatorLifetimeSeconds
    }
}

/// Request construction for conditional document fetches (RFC 9110 §13.1).
package enum ConditionalRequest {
    /// The stored validators to send, or nil for an unconditional request. Validators are used only when they came
    /// from the same address configuration and their full download is recent; a clock that moved backwards also
    /// forces a full download.
    package static func validators(
        from cursor: ConditionalCursor?, binding: String, now: Date, lifetimeSeconds: Double
    ) -> ConditionalCursor? {
        guard let cursor, cursor.binding == binding, cursor.hasValidators else { return nil }
        let age = now.timeIntervalSince(cursor.fullRetrievalAt)
        guard age >= 0, age < lifetimeSeconds else { return nil }
        return cursor
    }

    /// The GET request. It asks for the identity coding because the transport does not decode compressed content,
    /// and a request without Accept-Encoding allows any coding (RFC 9110 §12.5.3).
    package static func make(url: URL, accept: String, validators: ConditionalCursor?, bounds: FetchBounds)
        -> HTTPRequest
    {
        var headers = [HTTPHeader("Accept", accept), HTTPHeader("Accept-Encoding", "identity")]
        if let tag = validators?.entityTag { headers.append(HTTPHeader("If-None-Match", tag)) }
        // Sent together with If-None-Match for older intermediaries; a server then ignores it (RFC 9110 §13.1.3).
        if let date = validators?.lastModified { headers.append(HTTPHeader("If-Modified-Since", date)) }
        return HTTPRequest(
            method: "GET", url: url, headers: headers, timeoutSeconds: bounds.timeoutSeconds,
            connectTimeoutSeconds: bounds.connectTimeoutSeconds, maxResponseBytes: bounds.maxBytes,
            version: .any, redirects: .follow(max: bounds.maxRedirects), addresses: .publicOnly)
    }
}
