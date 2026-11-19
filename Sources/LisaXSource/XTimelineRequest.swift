// Builds the request for one page of an account's posts: GET /2/users/{id}/tweets on api.x.com with a bearer token.

import Foundation
import LisaHTTP
import LisaPorts
import LisaRedaction

/// The X API v2 user-posts request (https://docs.x.com/x-api/users/get-posts.md, operation `getUsersPosts`).
enum XTimelineRequest {
    /// The specification's only server.
    static let origin = "https://api.x.com"
    /// `max_results` accepts 5 to 100.
    static let pageSizeRange = 5...100
    /// The largest page accepted, whatever the synchronization limit: 100 posts of up to 25,000 characters fit.
    static let maxPageBytes = 16 * 1_048_576
    /// Connection setup (DNS, TCP, TLS) gets at most this long.
    static let connectTimeoutSeconds = 10.0

    /// The `max_results` for a pass: as many posts as the limit allows, up to 100.
    static func pageSize(for limits: SyncLimits) throws(ConnectorError) -> Int {
        guard limits.maxItems >= pageSizeRange.lowerBound else {
            throw ConnectorError(
                .configuration,
                "the X API returns at least 5 posts per request, so the synchronization item limit must be at least 5")
        }
        return min(limits.maxItems, pageSizeRange.upperBound)
    }

    /// The address of one page. `userID` must already be validated.
    static func url(userID: String, position: XTimelinePosition, pageSize: Int) -> URL? {
        var query = [("max_results", String(pageSize))]
        if let since = position.since { query.append(("since_id", since)) }
        if let next = position.window?.next { query.append(("pagination_token", next)) }
        query.append((XPostFields.parameterName, XPostFields.values.joined(separator: ",")))
        query.append((XPostFields.expansionsParameterName, XPostFields.expansions.joined(separator: ",")))
        let encoded = query.map { "\(escaped($0.0))=\(escaped($0.1))" }.joined(separator: "&")
        return URL(string: "\(origin)/2/users/\(userID)/tweets?\(encoded)")
    }

    /// The request for one page, authenticated with the app-only bearer token (`Authorization: Bearer <token>`,
    /// https://docs.x.com/resources/fundamentals/authentication/oauth-2-0/overview.md). Redirects are not followed, and
    /// only public internet addresses may be connected to.
    static func make(
        userID: String, position: XTimelinePosition, pageSize: Int, token: Sensitive<String>, limits: SyncLimits
    ) throws(ConnectorError) -> HTTPRequest {
        guard let url = url(userID: userID, position: position, pageSize: pageSize) else {
            throw ConnectorError(.internalError, "the X request address could not be formed")
        }
        let timeout = Double(min(max(1, limits.timeoutSeconds), 600))
        return HTTPRequest(
            method: "GET", url: url,
            headers: [
                HTTPHeader("Authorization", "Bearer \(token.revealed)", sensitive: true),
                HTTPHeader("Accept", "application/json"),
            ],
            timeoutSeconds: timeout, connectTimeoutSeconds: min(connectTimeoutSeconds, timeout),
            maxResponseBytes: max(1, min(limits.maxBytes, maxPageBytes)), version: .any, redirects: .none,
            addresses: .publicOnly)
    }

    /// Percent-encodes every byte except RFC 3986 unreserved characters and the comma that separates list values, as in
    /// X's examples (`tweet.fields=created_at,public_metrics`).
    static func escaped(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var result = ""
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E, 0x2C:
                result.append(Character(Unicode.Scalar(byte)))
            default:
                result.append("%")
                result.append(hex[Int(byte >> 4)])
                result.append(hex[Int(byte & 0x0F)])
            }
        }
        return result
    }
}
