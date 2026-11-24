// The operation and entity type names of the R2 operation catalog (plan §8.2.3).

/// The type names an operation envelope may carry. Payload schemas are defined per type as each milestone
/// implements it; the envelope codec treats the payload as an opaque canonical value.
public enum OperationCatalog {
    /// Operation types, `<entity>.<action>` (plan §8.2.3).
    public static let operationTypes: Set<String> = [
        "capture.create",
        "task.create", "task.edit", "task.complete", "task.cancel", "task.reopen",
        "note.add", "note.replaceObserved", "tags.change",
        "idea.create", "idea.edit", "idea.lifecycle",
        "reminder.create", "reminder.edit", "reminder.cancel",
        "occurrence.acknowledge", "occurrence.dismiss", "occurrence.snooze",
        "proposal.review", "proposal.dismiss", "proposal.correct",
        "preference.set", "preference.delete", "preference.confirm",
        "planBlock.accept", "planBlock.lock", "planBlock.reject", "planBlock.defer", "planBlock.complete",
        "planBlock.move",
        "planIntent.accept", "planIntent.lock", "planIntent.move", "planIntent.reject",
        "suggestion.propose", "suggestion.accept", "suggestion.dismiss",
        "item.delete", "item.restore",
        "conflict.resolve", "resolution.fallback",
        "device.keyUpdate",
        "authority.write",
    ]

    /// Entity types an operation's `entity` may name.
    public static let entityTypes: Set<String> = [
        "capture", "task", "idea", "reminder", "occurrence", "proposal", "preference", "planBlock", "planIntent",
        "suggestion", "conflict", "device", "item",
    ]

    /// The longest operation type name, used by the value-size derivation (plan §8.3.3).
    public static var longestOperationType: String { operationTypes.max { $0.utf8.count < $1.utf8.count } ?? "" }

    /// The longest entity type name.
    public static var longestEntityType: String { entityTypes.max { $0.utf8.count < $1.utf8.count } ?? "" }
}
