// The typed error model (API-03): stable codes with distinct HTTP statuses and messages free of secrets.

import Foundation

/// Error codes and their HTTP statuses.
public enum APIErrorCode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Malformed input or a failed validation (400).
    case invalidRequest
    /// Missing, unknown or revoked credentials (401).
    case unauthenticated
    /// The caller may not perform this action (403).
    case forbidden
    /// The route or entity does not exist (404).
    case notFound
    /// A revision check failed or the entity changed (409).
    case conflict
    /// The request body is larger than allowed (413).
    case payloadTooLarge
    /// A request ID was reused for a different request (422).
    case requestIDReused
    /// Too many requests; retry after the indicated delay (429).
    case throttled
    /// A temporary failure; retry later with the same request ID (503).
    case unavailable
    /// An unexpected failure; details are only in the host's redacted log (500).
    case internalError

    public var httpStatus: Int {
        switch self {
        case .invalidRequest: 400
        case .unauthenticated: 401
        case .forbidden: 403
        case .notFound: 404
        case .conflict: 409
        case .payloadTooLarge: 413
        case .requestIDReused: 422
        case .throttled: 429
        case .unavailable: 503
        case .internalError: 500
        }
    }

    /// Whether retrying the same request later can succeed.
    public var isRetryable: Bool { self == .throttled || self == .unavailable }
}

/// The body of every error response.
public struct APIErrorBody: Codable, Hashable, Sendable, Error {
    public var code: APIErrorCode
    /// A human-readable explanation without secrets or private content.
    public var message: String
    /// The offending field for validation errors.
    public var field: String?
    /// Suggested delay before retrying a throttled or unavailable request.
    public var retryAfterSeconds: Int?
    /// The entity's current revision when a revision check failed.
    public var currentRevision: Int64?

    public init(
        code: APIErrorCode, message: String, field: String? = nil, retryAfterSeconds: Int? = nil,
        currentRevision: Int64? = nil
    ) {
        self.code = code
        self.message = message
        self.field = field
        self.retryAfterSeconds = retryAfterSeconds
        self.currentRevision = currentRevision
    }
}
