// Errors of offline-queue operations: unknown entries, invalid or reused request IDs, limits and resolution rules.

import Foundation

/// Why an offline-queue operation was refused.
public enum OfflineQueueError: Error, Hashable, Sendable, CustomStringConvertible {
    /// No entry has this identifier.
    case entryNotFound(String)
    /// A request ID does not match `^[A-Za-z0-9._:-]{8,128}$`.
    case invalidRequestID(String)
    /// The request ID is already queued for a different request.
    case requestIDReused(String)
    /// The body is larger than the host accepts.
    case bodyTooLarge(bytes: Int, limit: Int)
    /// The queue already holds as many entries, or body bytes, as its configuration allows.
    case full(entryLimit: Int, byteLimit: Int)
    /// The entry's status does not allow the operation, for example discarding an entry that is being sent.
    case notAllowed(id: String, status: QueueEntryStatus)
    /// The mutation has no single expected revision to replace.
    case revisionNotApplicable(QueuedMutationKind)
    /// A stored entry does not match its kind and route.
    case malformedEntry(String)
    /// The request body could not be encoded.
    case encoding(String)

    public var description: String {
        switch self {
        case .entryNotFound(let id): "no queued request has the identifier \(id)"
        case .invalidRequestID(let value): "\"\(value)\" is not a valid request ID"
        case .requestIDReused(let id): "the request ID \(id) is already queued for a different request"
        case .bodyTooLarge(let bytes, let limit): "the request body has \(bytes) bytes; the host accepts \(limit)"
        case .full(let entryLimit, let byteLimit):
            "the offline queue is full (at most \(entryLimit) requests and \(byteLimit) body bytes)"
        case .notAllowed(let id, let status): "the queued request \(id) is \(status.rawValue) and cannot be changed so"
        case .revisionNotApplicable(let kind): "a \(kind.rawValue) request has no single expected revision to replace"
        case .malformedEntry(let detail): "a queued request is malformed: \(detail)"
        case .encoding(let detail): "the request could not be encoded: \(detail)"
        }
    }
}
