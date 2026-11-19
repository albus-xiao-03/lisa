// The truthful result of a user or Siri action: done, queued offline, unavailable, a recoverable conflict, or failed.

import Foundation
import LisaAPIContract
import LisaClient

/// What became of an action the owner took in the app, from a notification or through Siri (SIRI-01: truthful
/// success, offline-queued, unavailable and failure results). A queued action is never reported as done.
public enum ActionOutcome: Hashable, Sendable {
    /// The host applied the action.
    case done
    /// The action is saved durably on this device and is sent with this request ID once the host can be reached
    /// (after pairing again, when the host removed the device). It stays visible as pending until the host confirms
    /// it.
    case queued(requestID: String)
    /// The host cannot be reached (or this device is not paired) and the action could not be saved for later, so
    /// nothing happened.
    case unavailable(reason: String)
    /// The host refused the action because its subject changed; recoverable (`ActionConflict`).
    case conflict(ActionConflict)
    /// The action failed and was not applied, or its effect is unknown; the reason says which.
    case failed(reason: String)

    /// The outcome a queued entry stands for: done, pending, a conflict or a failure.
    public init(_ entry: QueuedRequest) {
        switch entry.status {
        case .done:
            self = .done
        case .pending, .sending:
            self = .queued(requestID: entry.requestID)
        case .conflict:
            self = .conflict(
                ActionConflict(
                    entryID: entry.id, currentRevision: entry.serverRevision,
                    message: entry.lastError?.message ?? Self.conflictMessage))
        case .failed:
            self = .failed(reason: entry.lastError?.message ?? "the host refused the action")
        }
    }

    /// The outcome of an action sent once, without the queue, that failed with `error`.
    init(unqueuedFailure error: ClientError) {
        switch error {
        case .notPaired:
            self = .unavailable(reason: Self.notPairedReason)
        case .transport(.unreachable), .transport(.refused):
            self = .unavailable(reason: error.description)
        case .transport(.interrupted), .cancelled:
            self = .failed(reason: Self.uncertainReason)
        case .api(let body, let status) where status == 409:
            self = .conflict(
                ActionConflict(entryID: nil, currentRevision: body.currentRevision, message: body.message))
        default:
            if error.isUnauthenticated {
                self = .failed(reason: Self.revokedReason)
            } else if error.isHostUnavailable {
                self = .unavailable(reason: error.description)
            } else {
                self = .failed(reason: error.description)
            }
        }
    }

    /// Whether the host applied the action.
    public var isDone: Bool { self == .done }

    /// Whether the action waits in the offline queue.
    public var isQueued: Bool {
        if case .queued = self { return true }
        return false
    }

    /// A sentence for the screen or for Siri, without the owner's content.
    public var summary: String {
        switch self {
        case .done: "Done."
        case .queued: "Saved on this device. It is sent to your Lisa host later and shown as pending until then."
        case .unavailable(let reason): "Lisa's host is unavailable, so nothing was saved: \(reason)."
        case .conflict: "This item changed on your host. Review it, then apply your change again or discard it."
        case .failed(let reason): "That didn't work: \(reason)."
        }
    }

    static let conflictMessage = "the item changed on the host since it was read"
    static let notPairedReason = "this device is not paired with a Lisa host"
    static let revokedReason = "the Lisa host removed this device; pair it again"
    static let uncertainReason =
        "the connection was interrupted, so the host may or may not have applied it; check the item before trying again"
}
