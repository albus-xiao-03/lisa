// Idea editing and lifecycle (IDEA-01). The original capture is preserved; edits change only the generated fields.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// An edit to an idea. `nil` leaves a field unchanged; `clearDeadline` removes the deadline.
public struct IdeaEdit: Hashable, Sendable {
    public var summary: String?
    public var tags: [String]?
    public var notes: String?
    public var priority: TaskPriority?
    public var estimatedMinutes: Int?
    public var deadline: Deadline?
    public var clearDeadline: Bool

    public init(
        summary: String? = nil, tags: [String]? = nil, notes: String? = nil, priority: TaskPriority? = nil,
        estimatedMinutes: Int? = nil, deadline: Deadline? = nil, clearDeadline: Bool = false
    ) {
        self.summary = summary
        self.tags = tags
        self.notes = notes
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.clearDeadline = clearDeadline
    }
}

/// Idea operations for the owner and paired devices.
public final class IdeaService: Sendable {
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    public func edit(_ id: IdeaID, expectedRevision: Revision, _ edit: IdeaEdit, by principal: Principal) throws -> Idea
    {
        try TaskService.requireOwnerOrDevice(principal)
        try TaskService.validateMinutes(edit.estimatedMinutes)
        let now = clock.now()
        return try store.write { tx in
            var idea = try tx.require(Idea.self, id: id)
            guard idea.revision == expectedRevision else {
                throw StoreError.conflict(
                    collection: Idea.collectionName, id: id.rawValue, expected: expectedRevision, actual: idea.revision)
            }
            if let summary = edit.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                idea.summary = String(summary.prefix(500))
            }
            if let tags = edit.tags {
                idea.tags = Array(
                    Set(tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
                )
                .sorted()
            }
            if let notes = edit.notes { idea.notes = notes }
            if let priority = edit.priority { idea.priority = priority }
            if let minutes = edit.estimatedMinutes { idea.estimatedMinutes = minutes }
            if edit.clearDeadline {
                idea.deadline = nil
            } else if let deadline = edit.deadline {
                idea.deadline = deadline
            }
            idea.updatedAt = now
            let saved = try tx.update(idea)
            try tx.insert(
                AuditEvent(
                    action: "idea.edited", actor: principal, at: now, affected: [id.rawValue], outcome: .succeeded,
                    detail: "lifecycle=\(saved.lifecycle.rawValue)"))
            return saved
        }
    }

    /// Moves an idea through its lifecycle. Scheduling an exploration block never marks the idea explored.
    public func transition(
        _ id: IdeaID, to lifecycle: IdeaLifecycle, expectedRevision: Revision?, by principal: Principal
    )
        throws -> Idea
    {
        try TaskService.requireOwnerOrDevice(principal)
        let now = clock.now()
        return try store.write { tx in
            var idea = try tx.require(Idea.self, id: id)
            if let expectedRevision, expectedRevision != idea.revision {
                throw StoreError.conflict(
                    collection: Idea.collectionName, id: id.rawValue, expected: expectedRevision, actual: idea.revision)
            }
            try idea.transition(to: lifecycle, at: now)
            if lifecycle != .availableForPlanning {
                idea.unschedulableReason = nil
                idea.unschedulableCount = 0
            }
            let saved = try tx.update(idea)
            try tx.insert(
                AuditEvent(
                    action: "idea.\(lifecycle.rawValue)", actor: principal, at: now, affected: [id.rawValue],
                    outcome: .succeeded, detail: ""))
            return saved
        }
    }
}
