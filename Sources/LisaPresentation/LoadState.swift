// What a screen shows while it loads data from the host: nothing yet, loading, the host's current data, cached data
// with its age while the host cannot be reached, or a failure. Cached data is never presented as current (UI-03).

import Foundation
import LisaClient

/// The state of one screen's data.
public enum LoadState<Value: Sendable>: Sendable {
    /// Nothing has been requested yet.
    case idle
    /// A request is in flight; `previous` is what the screen showed before.
    case loading(previous: ReadResult<Value>?)
    /// The latest answer, from the host or from the cache (`ReadResult.source` says which, with its age).
    case loaded(ReadResult<Value>)
    /// The request failed and the cache had nothing usable. `previous` is what the screen showed before, which is no
    /// longer current; it is `nil` when the failure means the owner's data must not be shown (`LoadFailure.hidesData`).
    case failed(LoadFailure, previous: ReadResult<Value>?)

    /// The data to show, current or not, if any.
    public var result: ReadResult<Value>? {
        switch self {
        case .idle: nil
        case .loading(let previous): previous
        case .loaded(let result): result
        case .failed(_, let previous): previous
        }
    }

    /// The value to show, current or not, if any.
    public var value: Value? { result?.value }

    /// Whether a request is in flight.
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Why the last request failed, if it did.
    public var failure: LoadFailure? {
        if case .failed(let failure, _) = self { return failure }
        return nil
    }

    /// Whether the data shown is not the host's current answer: a cached copy shown while the host is unreachable, or
    /// data kept on screen after a refresh failed. Show its age with it (`age(at:)`).
    public var isStale: Bool {
        switch self {
        case .idle: false
        case .loading(let previous): previous?.source == .cache
        case .loaded(let result): result.source == .cache
        case .failed(_, let previous): previous != nil
        }
    }

    /// How old the data shown is at `now`, or `nil` when nothing is shown.
    public func age(at now: Date) -> TimeInterval? {
        result?.age(at: now)
    }
}

extension LoadState: Equatable where Value: Equatable {}
