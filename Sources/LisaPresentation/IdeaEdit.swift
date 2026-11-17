// Changes the owner makes to an idea's details on the ideas screen; unset fields stay unchanged.

import Foundation
import LisaAPIContract

/// Changes to an idea's details (UI-01, IDEA-01: tags, notes, estimated exploration duration, priority and an
/// optional deadline). Fields left `nil` stay unchanged on the host; the owner's original capture is never changed.
public struct IdeaEdit: Hashable, Sendable {
    /// The longest summary the host keeps, in characters.
    public static let maxSummaryCharacters = 500
    /// The longest estimate the host accepts, in minutes.
    public static let maxEstimatedMinutes = 1_440

    /// A new summary.
    public var summary: String?
    /// New tags, replacing the current ones; the host stores them in lowercase without duplicates.
    public var tags: [String]?
    /// New notes.
    public var notes: String?
    /// A new priority.
    public var priority: TaskPriorityValue?
    /// A new estimated exploration duration in minutes.
    public var estimatedMinutes: Int?
    /// A new deadline.
    public var deadline: DeadlineDTO?
    /// Whether to remove the deadline.
    public var clearDeadline: Bool

    /// An edit setting the given fields.
    public init(
        summary: String? = nil, tags: [String]? = nil, notes: String? = nil, priority: TaskPriorityValue? = nil,
        estimatedMinutes: Int? = nil, deadline: DeadlineDTO? = nil, clearDeadline: Bool = false
    ) {
        self.summary = summary
        self.tags = tags
        self.notes = notes
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.clearDeadline = clearDeadline
    }

    /// Whether the edit changes nothing.
    public var isEmpty: Bool {
        summary == nil && tags == nil && notes == nil && priority == nil && estimatedMinutes == nil && deadline == nil
            && !clearDeadline
    }

    /// Why the edit cannot be sent, or `nil` when it can. The host checks the same rules and stays the authority.
    public var problem: String? {
        if isEmpty { return "Nothing was changed." }
        if let summary {
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "An idea needs a summary." }
            if trimmed.count > Self.maxSummaryCharacters {
                return "The summary is too long. Lisa keeps up to \(Self.maxSummaryCharacters) characters."
            }
        }
        if let estimatedMinutes, !(1...Self.maxEstimatedMinutes).contains(estimatedMinutes) {
            return "The estimate must be between 1 minute and 24 hours."
        }
        if let deadline, !deadline.isValid { return "The deadline is not a valid date or time." }
        if deadline != nil, clearDeadline { return "Choose either a new deadline or no deadline." }
        return nil
    }

    /// The patch for an idea the owner last saw at `expectedRevision`.
    func patch(expectedRevision: Int64) -> IdeaPatchRequest {
        IdeaPatchRequest(
            expectedRevision: expectedRevision, summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, notes: notes,
            priority: priority, estimatedMinutes: estimatedMinutes, deadline: deadline,
            clearDeadline: clearDeadline ? true : nil)
    }
}
