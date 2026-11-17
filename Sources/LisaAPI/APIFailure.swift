// Early-exit failures inside handlers and the mapping of service errors to typed API errors (API-03).

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDevices
import LisaDomain
import LisaPorts

/// A handler failure that becomes an error response.
struct APIFailure: Error {
    var body: APIErrorBody

    static func invalid(_ message: String, field: String? = nil) -> APIFailure {
        APIFailure(body: APIErrorBody(code: .invalidRequest, message: message, field: field))
    }

    static func notFound(_ what: String) -> APIFailure {
        APIFailure(body: APIErrorBody(code: .notFound, message: "\(what) does not exist"))
    }

    static func forbidden(_ message: String) -> APIFailure {
        APIFailure(body: APIErrorBody(code: .forbidden, message: message))
    }

    static func conflict(_ message: String, currentRevision: Int64? = nil) -> APIFailure {
        APIFailure(body: APIErrorBody(code: .conflict, message: message, currentRevision: currentRevision))
    }

    static let unauthenticated = APIFailure(
        body: APIErrorBody(code: .unauthenticated, message: "a valid device credential is required"))
}

/// Maps errors thrown by services to API errors without exposing private content.
enum ErrorMapping {
    static func body(for error: any Error) -> APIErrorBody {
        switch error {
        case let failure as APIFailure:
            return failure.body
        case let store as StoreError:
            switch store {
            case .notFound(let collection, _):
                return APIErrorBody(code: .notFound, message: "the \(singular(collection)) does not exist")
            case .conflict(_, _, _, let actual):
                return APIErrorBody(
                    code: .conflict, message: "the item changed since it was read; reload it and try again",
                    currentRevision: actual.value)
            case .duplicate(_, let field):
                return APIErrorBody(code: .conflict, message: "an item with the same \(field) already exists")
            case .unavailable:
                return APIErrorBody(
                    code: .unavailable, message: "the store is temporarily unavailable", retryAfterSeconds: 5)
            default:
                return APIErrorBody(code: .internalError, message: "the request could not be completed")
            }
        case let domain as DomainError:
            switch domain {
            case .invalidValue(let field, let reason):
                return APIErrorBody(code: .invalidRequest, message: "\(field) \(reason)", field: field)
            case .invalidTransition(let entity, let from, let to):
                return APIErrorBody(code: .conflict, message: "the \(entity) cannot move from \(from) to \(to)")
            case .notPermitted(let reason):
                return APIErrorBody(code: .forbidden, message: reason)
            case .revisionConflict(_, let actual):
                return APIErrorBody(
                    code: .conflict, message: "the item changed since it was read", currentRevision: actual.value)
            }
        case let device as DeviceError:
            switch device {
            case .invalidPairingCode, .revoked:
                return APIErrorBody(code: .unauthenticated, message: device.description)
            case .pairingAttemptsExceeded:
                return APIErrorBody(code: .throttled, message: device.description, retryAfterSeconds: 60)
            case .unknownDevice:
                return APIErrorBody(code: .notFound, message: device.description)
            case .topicNotAllowed, .environmentNotAllowed:
                return APIErrorBody(code: .forbidden, message: device.description)
            case .invalidToken:
                return APIErrorBody(code: .invalidRequest, message: device.description, field: "token")
            }
        case let page as CapturedPageError:
            return capturedPage(page)
        case is DecodingError:
            return APIErrorBody(code: .invalidRequest, message: "the request body does not match the documented schema")
        default:
            return APIErrorBody(code: .internalError, message: "the request could not be completed")
        }
    }

    /// Refusals of a captured link's retrieval: the capture's state is a conflict; a retrieval in progress, a temporary
    /// failure of the site and a host that cannot read links are temporary (not recorded, so a retry runs again).
    static func capturedPage(_ error: CapturedPageError) -> APIErrorBody {
        switch error {
        case .notRetrievable, .itemMissing, .alreadyRetrieved:
            APIErrorBody(code: .conflict, message: error.description)
        case .inProgress:
            APIErrorBody(code: .unavailable, message: error.description, retryAfterSeconds: 5)
        case .temporarilyUnavailable(_, let seconds):
            APIErrorBody(code: .unavailable, message: error.description, retryAfterSeconds: seconds)
        case .unavailable:
            APIErrorBody(code: .unavailable, message: error.description)
        }
    }

    static func singular(_ collection: String) -> String {
        switch collection {
        case "emails": "email"
        case "occurrences": "calendar event"
        case "proposals": "event proposal"
        case "news": "news item"
        case "audit": "audit record"
        default: collection.hasSuffix("s") ? String(collection.dropLast()) : collection
        }
    }
}
