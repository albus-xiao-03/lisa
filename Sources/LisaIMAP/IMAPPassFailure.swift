// Why one fetch pass ended without a batch: cancelled, or failed with a classified reason that is safe to store.

import LisaDomain
import LisaPorts

/// The outcome of a pass that produced no batch. The cursor never advances on a failure.
enum IMAPPassFailure: Error, Hashable, Sendable {
    /// The calling task was cancelled.
    case cancelled
    /// A classified failure; the summary is written by Lisa and holds no secret.
    case failed(SourceErrorClass, String)

    /// The error the connector throws: `CancellationError` for cancellation, otherwise a `ConnectorError`.
    var thrownError: any Error {
        switch self {
        case .cancelled: CancellationError()
        case .failed(let errorClass, let summary): ConnectorError(errorClass, summary)
        }
    }
}
