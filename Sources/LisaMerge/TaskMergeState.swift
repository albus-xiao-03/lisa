// One task's merged state (plan §8.3.1, §8.3.2): a multi-value register per editable field, note pieces, an
// observed-remove set per tag, terminal actions with explicit reopens, and the dominating tombstone. Every part is a
// join of what was applied, so replicas that applied the same operations hold the same state in any order. A tag
// removal covers only additions of its own tag, so a horizon never reaches another tag's additions. Operations arrive
// here decoded and verified; applying one again changes nothing.

import LisaSyncProtocol

/// The merge state of one task.
public struct TaskMergeState: Hashable, Sendable {
    /// The creating operation (the lowest ID if a forged copy named the same task).
    public private(set) var creation: Identifier128?
    public private(set) var title = MultiValueRegister<String>()
    public private(set) var priority = MultiValueRegister<String>()
    public private(set) var deadline = MultiValueRegister<WireDeadline?>()
    public private(set) var estimate = MultiValueRegister<Int64?>()
    public private(set) var splittable = MultiValueRegister<Bool>()
    public private(set) var confirmation = MultiValueRegister<String>()
    public private(set) var notes = NotePieces()
    public private(set) var tags: [String: ObservedRemoveSet<String>] = [:]
    public private(set) var status = TerminalActions()
    public private(set) var tombstone = ItemTombstone()
    /// Field edits, notes and tag changes: what a deletion supersedes.
    public private(set) var edits: Set<Identifier128> = []

    public init() {}

    /// Applies one operation of this task.
    /// - Parameters:
    ///   - observed: the operation's observed set; a creation observes nothing.
    ///   - commit: Core's commit position, when the operation is known committed.
    public mutating func apply(
        _ payload: ItemOperationPayload, id: Identifier128, authority: MergeAuthority = .owner,
        observed: ObservedCoverage, commit: CommitPosition? = nil
    ) {
        switch payload {
        case .taskCreate(let fields):
            if let existing = creation, existing.bytes.lexicographicallyPrecedes(id.bytes) {
            } else {
                creation = id
            }
            for value in fields.fieldValues {
                set(value, id: id, authority: authority, observed: .nothing, commit: commit)
            }
        case .taskEdit(let value):
            set(value, id: id, authority: authority, observed: observed, commit: commit)
            edits.insert(id)
        case .taskComplete:
            status.record(.completed, id: id, commit: commit)
        case .taskCancel:
            status.record(.cancelled, id: id, commit: commit)
        case .taskReopen(let reopens):
            if reopens.isEmpty {
                status.reopen(id: id, covering: observed)
            } else {
                status.reopen(naming: Set(reopens))
            }
        case .noteAdd(let text):
            notes.add(id: id, text: text, commit: commit)
            edits.insert(id)
        case .noteReplaceObserved(let text):
            notes.replaceObserved(id: id, text: text, observed: observed, commit: commit)
            edits.insert(id)
        case .tagChange(let tag, let added):
            var set = tags[tag, default: ObservedRemoveSet<String>()]
            if added { set.add(tag, id: id, commit: commit) } else { set.remove(id: id, observed: observed) }
            tags[tag] = set
            edits.insert(id)
        case .itemDelete:
            tombstone.delete(id: id)
        case .conflictResolve(_, let value):
            // A resolution replaces exactly the candidates it observed; a group page without a value changes nothing
            // until its group is complete, which the holder decides (plan §8.3.2).
            if let value {
                set(value, id: id, authority: authority, observed: observed, commit: commit)
                edits.insert(id)
            }
        }
    }

    /// Records Core's commit position for an operation applied while pending.
    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        title.markCommitted(id, at: commit)
        priority.markCommitted(id, at: commit)
        deadline.markCommitted(id, at: commit)
        estimate.markCommitted(id, at: commit)
        splittable.markCommitted(id, at: commit)
        confirmation.markCommitted(id, at: commit)
        notes.markCommitted(id, at: commit)
        status.markCommitted(id, at: commit)
        for tag in tags.keys { tags[tag]?.markCommitted(id, at: commit) }
    }

    public var view: TaskView {
        TaskView(
            exists: creation != nil, title: title.values.map(\.value), priority: priority.values.map(\.value),
            deadline: deadline.values.map(\.value), estimate: estimate.values.map(\.value),
            splittable: splittable.values.map(\.value), confirmation: confirmation.values.map(\.value),
            notes: notes.live.map(\.text),
            tags: tags.values.flatMap(\.elements).sorted {
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            },
            status: status.status, isDeleted: tombstone.isDeleted,
            supersededByDeletion: tombstone.isDeleted ? edits : [])
    }

    private mutating func set(
        _ value: TaskFieldValue, id: Identifier128, authority: MergeAuthority, observed: ObservedCoverage,
        commit: CommitPosition?
    ) {
        switch value {
        case .title(let v): title.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        case .priority(let v):
            priority.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        case .deadline(let v):
            deadline.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        case .estimate(let v):
            estimate.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        case .splittable(let v):
            splittable.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        case .confirmation(let v):
            confirmation.apply(id: id, value: v, authority: authority, observed: observed, commit: commit)
        }
    }
}
