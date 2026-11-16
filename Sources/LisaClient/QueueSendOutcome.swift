// How one send attempt of a queued request changes its entry, and whether the flush goes on.

import Foundation
import LisaAPIContract

/// The effect of one send attempt on a queued entry.
enum QueueSendOutcome: Equatable {
    /// The host applied the request.
    case applied(QueuedResponse)
    /// The subject changed on the host (409): a recoverable conflict. The flush goes on.
    case conflict(QueueEntryError, serverRevision: Int64?)
    /// The host refused the request for another reason. The flush goes on.
    case failed(QueueEntryError)
    /// The host asked the client to wait (429 or 503, or 502 or 504 from a proxy), optionally for `hostDelay` seconds.
    /// The request was not applied; the flush stops.
    case retryLater(QueueEntryError, hostDelay: Int?)
    /// The request did not complete: it stays pending and the flush stops because later requests would fare no
    /// better. `mayHaveBeenApplied` is true when the host may have received and applied it.
    case interrupted(QueueEntryError, mayHaveBeenApplied: Bool, cause: ClientError)

    /// Classifies the result of sending a queued request.
    static func classify(_ result: Result<APIResponse, ClientError>) -> QueueSendOutcome {
        switch result {
        case .success(let response):
            return .applied(QueuedResponse(status: response.status, body: response.body))
        case .failure(let error):
            return classify(error)
        }
    }

    private static func classify(_ error: ClientError) -> QueueSendOutcome {
        let entryError = QueueEntryError(error)
        switch error {
        case .api(let body, let status):
            return classify(status: status, error: error, entryError: entryError, body: body)
        case .unexpectedResponse(let status):
            return classify(status: status, error: error, entryError: entryError, body: nil)
        case .transport(let transportError):
            let uncertain = if case .interrupted = transportError { true } else { false }
            return .interrupted(entryError, mayHaveBeenApplied: uncertain, cause: error)
        case .cancelled, .incompatibleVersion:
            return .interrupted(entryError, mayHaveBeenApplied: true, cause: error)
        case .notPaired, .credentialStore:
            return .interrupted(entryError, mayHaveBeenApplied: false, cause: error)
        case .decoding, .encoding, .invalidRequestID, .invalidArgument:
            return .failed(entryError)
        }
    }

    private static func classify(
        status: Int, error: ClientError, entryError: QueueEntryError, body: APIErrorBody?
    ) -> QueueSendOutcome {
        if status == 409 { return .conflict(entryError, serverRevision: body?.currentRevision) }
        if status == 401 { return .interrupted(entryError, mayHaveBeenApplied: false, cause: error) }
        if ClientError.temporaryStatuses.contains(status) {
            return .retryLater(entryError, hostDelay: body?.retryAfterSeconds)
        }
        return .failed(entryError)
    }
}
