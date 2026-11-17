// Why the host refused a change of one preference: its validation message, or that this caller may not change it.

import Foundation

/// The host's refusal of a change to one preference (MEM-01), shown next to that preference: a value the host does not
/// accept, a key it does not support, or a consequential key that only the owner on the host may change.
public struct PreferenceIssue: Hashable, Sendable {
    /// The preference's key.
    public var key: String
    /// The host's explanation, such as "brief.targetWords must be a whole number between 50 and 3000".
    public var message: String
    /// The HTTP status of the refusal, when the host answered: 400 for a value it does not accept, 403 for a key this
    /// caller may not change.
    public var status: Int?
    /// The queued entry that still holds the refused change, for a change that was queued offline; `nil` when nothing
    /// is left in the queue.
    public var entryID: String?

    /// An issue with `key`.
    public init(key: String, message: String, status: Int? = nil, entryID: String? = nil) {
        self.key = key
        self.message = message
        self.status = status
        self.entryID = entryID
    }

    /// The explanation without the key it starts with, such as "must be a whole number between 50 and 3000", to show
    /// after the preference's title.
    public var reason: String {
        let prefix = key + " "
        guard message.hasPrefix(prefix) else { return message }
        return String(message.dropFirst(prefix.count))
    }

    /// Whether the host refused the change because this caller may not change the key: consequential keys are changed
    /// only by the owner on the host.
    public var isPermissionRefusal: Bool { status == 403 }
}
