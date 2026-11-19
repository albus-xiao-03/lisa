// Typed client errors (API-03): host error responses, transport failures, coding, version and pairing problems.

import Foundation
import LisaAPIContract

/// Why a client call failed. Descriptions never contain the device credential.
public enum ClientError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The host answered with an API error response.
    case api(APIErrorBody, status: Int)
    /// The host answered with a status outside 2xx and a body that is not an API error.
    case unexpectedResponse(status: Int)
    /// The request did not reach the host, or the connection failed after it may have been delivered.
    case transport(APITransportError)
    /// The call was cancelled before a response arrived; the request may have been delivered.
    case cancelled
    /// A success response could not be decoded.
    case decoding(String)
    /// The request body could not be encoded.
    case encoding(String)
    /// The host speaks an API major version this client does not support; the value is its `Lisa-API-Version`.
    case incompatibleVersion(String)
    /// The route needs a paired device and no device credential is stored.
    case notPaired
    /// A request ID does not match `^[A-Za-z0-9._:-]{8,128}$`.
    case invalidRequestID(String)
    /// An argument was rejected before sending, such as a malformed date or an out-of-range limit.
    case invalidArgument(name: String, reason: String)
    /// The credential store could not be read or written.
    case credentialStore(String)

    /// The HTTP status of the host's answer, when there was one.
    public var status: Int? {
        switch self {
        case .api(_, let status), .unexpectedResponse(let status): status
        default: nil
        }
    }

    /// The API error code, when the host answered with an error body.
    public var code: APIErrorCode? {
        if case .api(let body, _) = self { return body.code }
        return nil
    }

    /// Whether the host rejected the device credential (401): the device was removed and must pair again.
    public var isUnauthenticated: Bool { status == 401 }

    /// Whether the host refused the request because its subject changed (409).
    public var isConflict: Bool { status == 409 }

    /// Whether the host could not be reached or asked to retry later, so cached data and queued mutations apply.
    public var isHostUnavailable: Bool {
        switch self {
        case .transport: true
        case .api(_, let status), .unexpectedResponse(let status): Self.temporaryStatuses.contains(status)
        default: false
        }
    }

    /// Statuses that mean "try again later": throttled, bad gateway, unavailable and gateway timeout.
    static let temporaryStatuses: Set<Int> = [429, 502, 503, 504]

    public var description: String {
        switch self {
        case .api(let body, let status):
            "the Lisa host refused the request (\(status) \(body.code.rawValue)): \(body.message)"
        case .unexpectedResponse(let status): "the Lisa host answered with the unexpected status \(status)"
        case .transport(let error): error.description
        case .cancelled: "the request was cancelled"
        case .decoding(let detail): "the Lisa host's response could not be read: \(detail)"
        case .encoding(let detail): "the request could not be encoded: \(detail)"
        case .incompatibleVersion(let version):
            "the Lisa host uses API version \(version), which this client does not support"
        case .notPaired: "this device is not paired with a Lisa host"
        case .invalidRequestID(let value): "\"\(value)\" is not a valid request ID"
        case .invalidArgument(let name, let reason): "invalid \(name): \(reason)"
        case .credentialStore(let detail): "the device identity could not be accessed: \(detail)"
        }
    }
}
