// Classifies the outcome of a document fetch: HTTP statuses and transport failures become source error classes with
// summaries that show at most the origin, and Retry-After becomes the source's earliest retry time.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts

/// A response that can be used.
package enum FetchOutcome: Sendable {
    /// A full representation (200 or 203); its content still has to be checked.
    case content(HTTPResponse)
    /// A 304 to a conditional request: the stored state is current and nothing was transferred.
    case notModified(HTTPResponse)
}

/// Status and failure classification (INGEST-01 retry classification and rate-limit handling).
package enum ResponseClassification {
    /// The longest transport text passed through into a summary.
    package static let maxDetailLength = 160

    /// What `response` means. `conditional` says whether validators were sent: a 304 to an unconditional request is a
    /// server error, never "unchanged", and certainly never an empty document.
    package static func outcome(
        of response: HTTPResponse, conditional: Bool, subject: String, now: Date
    ) -> Result<FetchOutcome, ConnectorError> {
        let status = response.status
        let retryAfter = RetryAfter.date(in: response, now: now)
        switch status {
        case 200, 203:
            return .success(.content(response))
        case 304 where conditional:
            return .success(.notModified(response))
        case 304:
            return .failure(
                ConnectorError(
                    .partial,
                    "the server answered \"not modified\" (304) although Lisa sent no stored validators; nothing was"
                        + " changed"))
        case 204, 205:
            return .failure(ConnectorError(.parse, "the server returned no \(subject) (status \(status))"))
        case 206:
            return .failure(ConnectorError(.partial, "the server returned only part of the \(subject) (status 206)"))
        case 201...299:
            return .failure(
                ConnectorError(.partial, "the server returned status \(status) instead of the \(subject)"))
        case 300...399:
            return .failure(
                ConnectorError(
                    .configuration,
                    "the server answered with a redirect (status \(status)) that Lisa could not follow"))
        case 401:
            return .failure(
                ConnectorError(
                    .authentication,
                    "the server requires authentication (status 401); a private address may have been reset or have"
                        + " expired"))
        case 403:
            return .failure(
                ConnectorError(.permissionDenied, "the server refused access to the \(subject) (status 403)"))
        case 404:
            return .failure(
                ConnectorError(
                    .configuration, "the \(subject) was not found (status 404); it may have moved or been removed"))
        case 410:
            return .failure(
                ConnectorError(.configuration, "the server reports that the \(subject) is gone for good (status 410)"))
        case 408:
            return .failure(ConnectorError(.timeout, "the server timed out waiting for the request (status 408)"))
        case 429:
            return .failure(
                ConnectorError(
                    .rateLimited, "the server is limiting requests (status 429)" + waitSuffix(retryAfter, now: now),
                    retryAfter: retryAfter))
        case 451:
            return .failure(
                ConnectorError(.permissionDenied, "the server may not provide the \(subject) (status 451)"))
        case 400...499:
            return .failure(ConnectorError(.configuration, "the server rejected the request (status \(status))"))
        case 503:
            return .failure(
                ConnectorError(
                    .network, "the server is temporarily unavailable (status 503)" + waitSuffix(retryAfter, now: now),
                    retryAfter: retryAfter))
        case 504:
            return .failure(
                ConnectorError(.timeout, "the server's gateway timed out (status 504)", retryAfter: retryAfter))
        case 500...599:
            return .failure(
                ConnectorError(.network, "the server failed (status \(status))", retryAfter: retryAfter))
        default:
            return .failure(ConnectorError(.network, "the server sent an unexpected status (\(status))"))
        }
    }

    /// The classified error for a transport failure. The transport's own text is generic, but it is still scrubbed
    /// of the address and bounded before it is kept.
    package static func error(for failure: HTTPFailure, subject: String, scrubber: SecretScrubber) -> ConnectorError {
        switch failure {
        case .refused(let reason):
            return ConnectorError(
                .configuration, "Lisa's network policy refused the request: \(detail(reason, scrubber))")
        case .unsupported(let reason):
            return ConnectorError(.unsupported, "the transport cannot perform the request: \(detail(reason, scrubber))")
        case .cancelled:
            return ConnectorError(.timeout, "the retrieval of the \(subject) was cancelled")
        case .notSent(let reason):
            return ConnectorError(.network, "the server could not be reached: \(detail(reason, scrubber))")
        case .untrustedServer(let reason):
            return ConnectorError(
                .network, "the server's certificate could not be verified: \(detail(reason, scrubber))")
        case .http2Unavailable:
            return ConnectorError(.unsupported, "the server did not negotiate HTTP/2")
        case .timedOut:
            return ConnectorError(.timeout, "the server did not answer in time")
        case .connectionLost(_, let reason):
            return ConnectorError(.network, "the connection was lost: \(detail(reason, scrubber))")
        case .responseTooLarge(let limit):
            return tooLarge(subject: subject, limit: limit)
        case .redirectRefused(let reason):
            return ConnectorError(.configuration, "a redirect was refused: \(detail(reason, scrubber))")
        case .protocolError(let reason):
            return ConnectorError(.network, "the server's reply was not valid HTTP: \(detail(reason, scrubber))")
        }
    }

    /// The error for a document larger than the limit: retrying cannot help, raising the limit can.
    package static func tooLarge(subject: String, limit: Int) -> ConnectorError {
        ConnectorError(.configuration, "the \(subject) is larger than the size limit of \(limit) bytes")
    }

    private static func detail(_ text: String, _ scrubber: SecretScrubber) -> String {
        let scrubbed = scrubber.scrub(text)
        return scrubbed.count > maxDetailLength ? String(scrubbed.prefix(maxDetailLength)) + "…" : scrubbed
    }

    private static func waitSuffix(_ retryAfter: Date?, now: Date) -> String {
        guard let retryAfter else { return "" }
        return "; it asked Lisa to wait \(max(0, Int(retryAfter.timeIntervalSince(now).rounded()))) seconds"
    }
}
