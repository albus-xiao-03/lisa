// Tasks the owner creates, corrects and moves through their lifecycle; corrections take precedence (DATA-04).

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// A new manual task.
public struct TaskDraft: Hashable, Sendable {
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var deadline: Deadline?
    public var estimatedMinutes: Int?
    public var splittable: Bool

    public init(
        title: String, notes: String = "", priority: TaskPriority = .normal, deadline: Deadline? = nil,
        estimatedMinutes: Int? = nil, splittable: Bool = false
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.splittable = splittable
    }
}

/// An owner correction. `nil` leaves a field unchanged; `clearDeadline` removes the deadline.
public struct TaskCorrection: Hashable, Sendable {
    public var title: String?
    public var notes: String?
    public var priority: TaskPriority?
    public var deadline: Deadline?
    public var clearDeadline: Bool
    public var estimatedMinutes: Int?
    public var confirmation: Confirmation?

    public init(
        title: String? = nil, notes: String? = nil, priority: TaskPriority? = nil, deadline: Deadline? = nil,
        clearDeadline: Bool = false, estimatedMinutes: Int? = nil, confirmation: Confirmation? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.deadline = deadline
        self.clearDeadline = clearDeadline
        self.estimatedMinutes = estimatedMinutes
        self.confirmation = confirmation
    }
}

/// A task after a change, with the domain changes to propagate.
public struct TaskUpdate: Sendable {
    public var task: LisaTask
    public var changes: [DomainChange]
}

/// Task operations for the owner and paired devices. Models never call these; extraction has its own path.
public final class TaskService: Sendable {
    public static let maxTitleCharacters = 200
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    public func create(_ draft: TaskDraft, by principal: Principal) throws -> TaskUpdate {
        try Self.requireOwnerOrDevice(principal)
        let title = try Self.validTitle(draft.title)
        try Self.validateMinutes(draft.estimatedMinutes)
        let now = clock.now()
        let task = try store.write { tx -> LisaTask in
            let saved = try tx.insert(
                LisaTask(
                    title: title, notes: draft.notes, priority: draft.priority, deadline: draft.deadline,
                    estimatedMinutes: draft.estimatedMinutes, splittable: draft.splittable, confirmation: .confirmed,
                    origin: .manual, now: now))
            try tx.insert(Self.audit("task.created", saved, principal, now))
            return saved
        }
        return TaskUpdate(task: task, changes: [.taskCreated(task.id)])
    }

    /// Applies an owner correction. Each changed field is marked owner-corrected so reprocessing never overwrites it.
    public func correct(_ id: TaskID, expectedRevision: Revision, _ correction: TaskCorrection, by principal: Principal)
        throws -> TaskUpdate
    {
        try Self.requireOwnerOrDevice(principal)
        try Self.validateMinutes(correction.estimatedMinutes)
        let title = try correction.title.map(Self.validTitle)
        let now = clock.now()
        return try store.write { tx in
            var task = try tx.require(LisaTask.self, id: id)
            try Self.check(expectedRevision, task.revision, id.rawValue)
            var material = false
            if let title, title != task.title {
                task.title = title
                task.ownerCorrected.insert(.title)
            }
            if let notes = correction.notes { task.notes = notes }
            if let priority = correction.priority, priority != task.priority {
                task.priority = priority
                task.ownerCorrected.insert(.priority)
                material = true
            }
            if correction.clearDeadline || correction.deadline != nil {
                let deadline = correction.clearDeadline ? nil : correction.deadline
                if deadline != task.deadline {
                    task.deadline = deadline
                    task.unresolvedDeadlineText = nil
                    material = true
                }
                task.ownerCorrected.insert(.deadline)
            }
            if let minutes = correction.estimatedMinutes, minutes != task.estimatedMinutes {
                task.estimatedMinutes = minutes
                task.ownerCorrected.insert(.duration)
            }
            if let confirmation = correction.confirmation, confirmation != task.confirmation {
                task.confirmation = confirmation
                task.ownerCorrected.insert(.confirmation)
                material = true
            }
            if material { task.changeSequence += 1 }
            task.updatedAt = now
            let saved = try tx.update(task)
            try tx.insert(Self.audit("task.corrected", saved, principal, now))
            return TaskUpdate(task: saved, changes: [.taskChanged(id, material: material)])
        }
    }

    /// Moves a task through its lifecycle (complete, cancel, reopen, start, block).
    public func transition(_ id: TaskID, to status: TaskStatus, expectedRevision: Revision?, by principal: Principal)
        throws -> TaskUpdate
    {
        try Self.requireOwnerOrDevice(principal)
        let now = clock.now()
        return try store.write { tx in
            var task = try tx.require(LisaTask.self, id: id)
            if let expectedRevision { try Self.check(expectedRevision, task.revision, id.rawValue) }
            try task.transition(to: status, at: now)
            if task.origin == .extracted { task.ownerCorrected.insert(.status) }
            let saved = try tx.update(task)
            try tx.insert(Self.audit("task.\(status.rawValue)", saved, principal, now))
            let change: DomainChange =
                switch status {
                case .completed: .taskCompleted(id)
                case .cancelled: .taskCancelled(id)
                case .open, .inProgress, .blocked: .taskChanged(id, material: true)
                }
            return TaskUpdate(task: saved, changes: [change])
        }
    }

    static func requireOwnerOrDevice(_ principal: Principal) throws {
        switch principal {
        case .localOwner, .pairedDevice, .demonstration: return
        case .runtime, .model: throw DomainError.notPermitted("tasks are changed only by the owner")
        }
    }

    static func validTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTitleCharacters else {
            throw DomainError.invalidValue(field: "title", reason: "must be 1 to \(maxTitleCharacters) characters")
        }
        return trimmed
    }

    static func validateMinutes(_ minutes: Int?) throws {
        if let minutes, !(1...1440).contains(minutes) {
            throw DomainError.invalidValue(field: "estimatedMinutes", reason: "must be between 1 and 1440")
        }
    }

    static func check(_ expected: Revision, _ actual: Revision, _ id: String) throws {
        guard expected == actual else {
            throw StoreError.conflict(collection: LisaTask.collectionName, id: id, expected: expected, actual: actual)
        }
    }

    static func audit(_ action: String, _ task: LisaTask, _ principal: Principal, _ now: Date) -> AuditEvent {
        AuditEvent(
            action: action, actor: principal, at: now, affected: [task.id.rawValue], outcome: .succeeded,
            detail: "status=\(task.status.rawValue) revision=\(task.revision)")
    }
}
