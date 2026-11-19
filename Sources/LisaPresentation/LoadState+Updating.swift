// Changing the data a screen shows without changing where its state stands, as when an action returns a newer item.

import Foundation
import LisaClient

extension LoadState {
    /// The same state with the data it shows changed by `update`; a state that shows nothing is returned unchanged.
    /// Used when an action returns a newer version of an item on screen. Where the data came from, and its age, stay
    /// as they were.
    func updatingShown(_ update: (inout Value) -> Void) -> LoadState<Value> {
        switch self {
        case .idle:
            return self
        case .loading(let previous):
            guard var shown = previous else { return self }
            update(&shown.value)
            return .loading(previous: shown)
        case .loaded(var shown):
            update(&shown.value)
            return .loaded(shown)
        case .failed(let failure, let previous):
            guard var shown = previous else { return self }
            update(&shown.value)
            return .failed(failure, previous: shown)
        }
    }
}
