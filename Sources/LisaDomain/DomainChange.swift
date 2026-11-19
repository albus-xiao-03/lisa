// Change events produced by ingestion and owner actions, used to invalidate plans, reminders and briefs.

/// A change that other parts of the application may need to react to.
public enum DomainChange: Hashable, Codable, Sendable {
    case occurrenceAdded(OccurrenceID)
    case occurrenceChanged(OccurrenceID, summary: String)
    case occurrenceCancelled(OccurrenceID)
    case occurrenceRemoved(OccurrenceID)
    case taskCreated(TaskID)
    case taskChanged(TaskID, material: Bool)
    case taskCompleted(TaskID)
    case taskCancelled(TaskID)
    case proposalChanged(ProposalID)
    case ideaChanged(IdeaID)
    case preferenceChanged(PreferenceKey)
    case sourceHealthChanged(SourceID)
    case timeZoneChanged

    /// Whether the change can affect the daily plan.
    public var affectsPlanning: Bool {
        switch self {
        case .occurrenceAdded, .occurrenceChanged, .occurrenceCancelled, .occurrenceRemoved, .taskCreated,
            .taskCompleted, .taskCancelled, .ideaChanged, .timeZoneChanged, .sourceHealthChanged:
            true
        case .taskChanged(_, let material): material
        case .preferenceChanged, .proposalChanged: true
        }
    }
}
