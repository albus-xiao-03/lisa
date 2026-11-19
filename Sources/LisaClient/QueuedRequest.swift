// One durable offline-queue entry: identity, route, body, attempts, status, last error and the retained response.

import Foundation
import LisaAPIContract

/// Where a queued request stands.
public enum QueueEntryStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// Waiting to be sent, possibly again after an attempt that did not complete.
    case pending
    /// Being sent now. An entry found in this state when the queue is loaded is pending again.
    case sending
    /// The host refused it because its subject changed (409). Recoverable: discard it, or re-queue it with a new
    /// expected revision.
    case conflict
    /// The host refused it for another reason. Discard it, or re-queue it to try again.
    case failed
    /// The host applied it. The response is kept for the UI until the entry is pruned.
    case done
}

/// Why the last attempt of a queued request did not succeed.
public struct QueueEntryError: Codable, Hashable, Sendable, CustomStringConvertible {
    /// The HTTP status, when the host answered.
    public var status: Int?
    /// The API error code, when the host answered with an error body.
    public var code: APIErrorCode?
    /// A human-readable explanation without secrets.
    public var message: String
    /// The offending field of a validation error.
    public var field: String?

    /// An error with the host's status, code and field when the host answered.
    public init(status: Int? = nil, code: APIErrorCode? = nil, message: String, field: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.field = field
    }

    /// The error a failed send leaves on its entry.
    init(_ error: ClientError) {
        switch error {
        case .api(let body, let status):
            self.init(status: status, code: body.code, message: body.message, field: body.field)
        case .unexpectedResponse(let status):
            self.init(status: status, message: error.description)
        default:
            self.init(message: error.description)
        }
    }

    public var description: String { message }
}

/// A success response kept on an applied entry.
public struct QueuedResponse: Codable, Hashable, Sendable {
    /// The HTTP status of the success response.
    public var status: Int
    /// The JSON body as the host sent it.
    public var body: Data

    /// A success response with `status` and `body`.
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// A mutation waiting in, or recently sent from, the offline queue (UI-03, NOTIFY-05).
public struct QueuedRequest: Codable, Hashable, Sendable, Identifiable, CustomStringConvertible {
    /// The entry's stable identity: the request ID assigned once, at enqueue time.
    public let id: String
    /// The request ID sent to the host. Every retry sends the same ID, so the host applies the request once. It differs
    /// from `id` only after the owner re-queued a conflicting or failed entry, which the host refused without applying.
    public internal(set) var requestID: String
    /// What the queued mutation is.
    public let kind: QueuedMutationKind
    /// The HTTP method, sent exactly as queued.
    public let method: HTTPMethod
    /// The request path, sent exactly as queued.
    public let path: String
    /// The JSON body, sent exactly as queued.
    public internal(set) var body: Data
    /// When the entry was queued.
    public let createdAt: Date
    /// Where the entry stands.
    public internal(set) var status: QueueEntryStatus
    /// How many times the request was sent.
    public internal(set) var attempts: Int
    /// When the request was last sent.
    public internal(set) var lastAttemptAt: Date?
    /// The earliest time to send again, after the host asked the client to wait (429 or 503).
    public internal(set) var nextAttemptAt: Date?
    /// The first time an attempt ended without a definite answer, so the host may have applied the request. Retrying
    /// with the same request ID is safe only while the host still remembers it
    /// (`APIVersioning.idempotencyRetentionDays`).
    public internal(set) var uncertainSince: Date?
    /// Why the last attempt did not succeed.
    public internal(set) var lastError: QueueEntryError?
    /// The subject's current revision on the host, from a conflict response.
    public internal(set) var serverRevision: Int64?
    /// The host's success response, kept once the entry is done.
    public internal(set) var response: QueuedResponse?
    /// When the host applied the request.
    public internal(set) var completedAt: Date?

    init(id: String, mutation: QueuedMutation, body: Data, createdAt: Date) {
        self.id = id
        requestID = id
        kind = mutation.kind
        method = mutation.route.method
        path = mutation.route.path
        self.body = body
        self.createdAt = createdAt
        status = .pending
        attempts = 0
    }

    /// The route the entry's method and path address.
    public var route: APIRoute? { APIRoute.match(method: method, path: path) }

    /// Whether the entry still waits for the host: pending or being sent.
    public var isAwaitingHost: Bool { status == .pending || status == .sending }

    /// Whether the owner must resolve the entry: a conflict or a failure.
    public var needsResolution: Bool { status == .conflict || status == .failed }

    /// The queued mutation, decoded from the entry's route and body.
    public func mutation() throws -> QueuedMutation {
        guard let route else { throw OfflineQueueError.malformedEntry("entry \(id) has an unknown route") }
        return try QueuedMutation(kind: kind, route: route, body: body)
    }

    /// The host's success response decoded as `type`, or `nil` while the entry is not done.
    public func decodedResponse<Response: Decodable>(as type: Response.Type) throws -> Response? {
        guard let response else { return nil }
        return try APIJSON.decoder().decode(type, from: response.body)
    }

    /// Identifies the entry without its body, which may hold private content.
    public var description: String {
        "QueuedRequest(\(id), \(kind.rawValue), \(status.rawValue), attempts: \(attempts))"
    }
}
