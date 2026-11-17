// A preference change the host refused because the preference changed meanwhile, with the change and the current
// preference.

import Foundation
import LisaAPIContract

/// A change of one preference that the host refused because the preference changed since the owner saw it (UI-03).
/// The memory screen shows the current preference next to the refused change; the owner applies the change again to
/// the current version or discards it.
public struct PreferenceConflict: Hashable, Sendable {
    /// The preference's key.
    public var key: String
    /// The refused change, with its queued entry and the preference's current revision.
    public var conflict: ActionConflict
    /// The change that was refused.
    public var change: PreferenceChange?
    /// The preference as the host has it now, once it was read.
    public var current: PreferenceDTO?

    /// A conflict on `key`.
    public init(key: String, conflict: ActionConflict, change: PreferenceChange?, current: PreferenceDTO?) {
        self.key = key
        self.conflict = conflict
        self.change = change
        self.current = current
    }
}
