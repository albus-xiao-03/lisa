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
    /// The request failed and nothing usable was cached; `previous` is what the screen showed before.
    case failed(message: String, previous: ReadResult<Value>?)

    /// The data to show, current or cached, if any.
    public var result: ReadResult<Value>? {
        switch self {
        case .idle: nil
        case .loading(let previous): previous
        case .loaded(let result): result
        case .failed(_, let previous): previous
        }
    }

    /// Whether a request is in flight.
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
