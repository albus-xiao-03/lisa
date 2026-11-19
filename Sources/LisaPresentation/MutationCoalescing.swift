// Merging two queued changes of the same subject the host has not applied, so a second offline edit is no conflict.

import Foundation
import LisaAPIContract
import LisaClient

/// Merges a new change into an earlier queued change of the same subject that the host has not applied (UI-03).
///
/// Two task patches or two notification-preference patches made offline both expect the revision the owner saw. Sent
/// one after the other, the second would always conflict with the first. When the host cannot have applied the
/// first, the queue holds one merged patch instead, which still expects the revision the owner saw, so a newer state
/// on the host is still a conflict and never overwritten.
enum MutationCoalescing {
    /// The mutation with the effect of `earlier` followed by `later`, when both change the same subject and expect the
    /// same revision; `nil` otherwise.
    static func merge(_ earlier: QueuedMutation, _ later: QueuedMutation) -> QueuedMutation? {
        switch (earlier, later) {
        case (.updateTask(let firstID, let first), .updateTask(let secondID, let second)):
            guard firstID == secondID, first.expectedRevision == second.expectedRevision else { return nil }
            return .updateTask(id: firstID, merge(first, second))
        case (.updateNotificationPreferences(let first), .updateNotificationPreferences(let second)):
            guard first.expectedRevision == second.expectedRevision else { return nil }
            var merged = first
            if let enabled = second.enabled { merged.enabled = enabled }
            if let categories = second.categories { merged.categories = categories }
            if let showTitles = second.showTitles { merged.showTitles = showTitles }
            if let allow = second.allowTimeSensitive { merged.allowTimeSensitive = allow }
            return .updateNotificationPreferences(merged)
        default:
            return nil
        }
    }

    /// `first` with every field `second` sets.
    private static func merge(_ first: TaskPatchRequest, _ second: TaskPatchRequest) -> TaskPatchRequest {
        var merged = first
        if let status = second.status { merged.status = status }
        if let title = second.title { merged.title = title }
        if let notes = second.notes { merged.notes = notes }
        if let priority = second.priority { merged.priority = priority }
        if second.clearDeadline == true {
            merged.deadline = nil
            merged.clearDeadline = true
        }
        if let deadline = second.deadline {
            merged.deadline = deadline
            merged.clearDeadline = nil
        }
        if let minutes = second.estimatedMinutes { merged.estimatedMinutes = minutes }
        if let confirmation = second.confirmation { merged.confirmation = confirmation }
        return merged
    }
}
