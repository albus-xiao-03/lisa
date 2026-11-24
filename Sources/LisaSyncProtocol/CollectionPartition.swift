// The partitions of unwindowed collections (plan §8.4.2): tasks, ideas, captures, preferences, proposals, owner
// reminders and suggestions are one partition each. Plans, briefs and calendar occurrences are windowed by date and
// get their partitions from their buckets instead.

/// Partition names of the unwindowed collections.
public enum CollectionPartition {
    /// The partition holding items of `entityType`, or `nil` for a windowed or unpartitioned type.
    public static func name(forEntityType entityType: String) -> String? {
        switch entityType {
        case "task": "tasks"
        case "idea": "ideas"
        case "capture": "captures"
        case "preference": "preferences"
        case "proposal": "proposals"
        case "reminder": "reminders"
        case "suggestion": "suggestions"
        default: nil
        }
    }
}
