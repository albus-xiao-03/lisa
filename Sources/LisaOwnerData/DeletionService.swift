// Deletion of individual items and preferences (DATA-05), invalidating records generated from them.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// An item the owner can delete.
public enum DeletableItem: Hashable, Sendable {
    case capture(CaptureID)
    case idea(IdeaID)
    case task(TaskID)
    case news(NewsID)
    case email(EmailID)
    case proposal(ProposalID)
    case preference(PreferenceKey)
}

/// What a deletion removed and what must be recomputed.
public struct DeletionResult: Hashable, Sendable {
    /// Deleted records as `collection:id`.
    public var deleted: [String]
    /// Changes the application facade feeds to planning, reminders and briefs.
    public var changes: [DomainChange]
    /// Briefs marked stale because they referenced a deleted record.
    public var staleBriefs: [BriefID]
}

/// Deletes items. Deleting is permanent: the records and their raw content are removed, not hidden.
public final class DeletionService: Sendable {
    private let store: any RecordStore
    private let raw: any RawContentStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, raw: any RawContentStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.raw = raw
        self.clock = clock
        self.logger = logger
    }

    public func delete(_ item: DeletableItem, by principal: Principal) throws -> DeletionResult {
        guard principal.mayChangeConsequentialSettings || Self.devicesMayDelete(item, principal) else {
            throw DomainError.notPermitted("this item can only be deleted by the owner on the host")
        }
        let now = clock.now()
        var rawRefs: [String] = []
        let result = try store.write { tx -> DeletionResult in
            var deleted: [String] = []
            var changes: [DomainChange] = []
            var evidence: Set<EvidenceID> = []
            var records: Set<String> = []
            switch item {
            case .capture(let id):
                let capture = try tx.require(Capture.self, id: id)
                try tx.delete(Capture.self, id: id)
                deleted.append("captures:\(id.rawValue)")
                records.insert(id.rawValue)
                if let ideaID = capture.resultingIdeaID, try tx.get(Idea.self, id: ideaID) != nil {
                    try tx.delete(Idea.self, id: ideaID)
                    deleted.append("ideas:\(ideaID.rawValue)")
                    records.insert(ideaID.rawValue)
                    changes.append(.ideaChanged(ideaID))
                }
            case .idea(let id):
                let idea = try tx.require(Idea.self, id: id)
                try tx.delete(Idea.self, id: id)
                deleted.append("ideas:\(id.rawValue)")
                records.insert(id.rawValue)
                changes.append(.ideaChanged(id))
                if let captureID = idea.captureID, try tx.get(Capture.self, id: captureID) != nil {
                    try tx.delete(Capture.self, id: captureID)
                    deleted.append("captures:\(captureID.rawValue)")
                }
            case .task(let id):
                _ = try tx.require(LisaTask.self, id: id)
                try tx.delete(LisaTask.self, id: id)
                deleted.append("tasks:\(id.rawValue)")
                records.insert(id.rawValue)
                changes.append(.taskCancelled(id))
            case .news(let id):
                let news = try tx.require(NewsItem.self, id: id)
                try tx.delete(NewsItem.self, id: id)
                deleted.append("news:\(id.rawValue)")
                records.insert(id.rawValue)
                evidence.insert(news.evidenceID)
            case .email(let id):
                let email = try tx.require(EmailMessage.self, id: id)
                try tx.delete(EmailMessage.self, id: id)
                deleted.append("emails:\(id.rawValue)")
                records.insert(id.rawValue)
                evidence.insert(email.evidenceID)
            case .proposal(let id):
                _ = try tx.require(EventProposal.self, id: id)
                try tx.delete(EventProposal.self, id: id)
                deleted.append("proposals:\(id.rawValue)")
                records.insert(id.rawValue)
                changes.append(.proposalChanged(id))
            case .preference(let key):
                guard
                    let preference = try tx.first(Preference.self, RecordQuery.all.filter("key", equals: key.rawValue))
                else { throw StoreError.notFound(collection: Preference.collectionName, id: key.rawValue) }
                if key.isConsequential, !principal.mayChangeConsequentialSettings {
                    throw DomainError.notPermitted("consequential preferences can only be changed by the owner")
                }
                try tx.delete(Preference.self, id: preference.id)
                deleted.append("preferences:\(key.rawValue)")
                changes.append(.preferenceChanged(key))
            }
            for evidenceID in evidence {
                if let record = try tx.get(Evidence.self, id: evidenceID) {
                    if let ref = record.contentRef { rawRefs.append(ref) }
                    try tx.delete(Evidence.self, id: evidenceID)
                    deleted.append("evidence:\(evidenceID.rawValue)")
                    records.insert(evidenceID.rawValue)
                }
            }
            _ = try Self.unlinkEvidence(evidence, at: now, in: tx)
            let stale = try Self.markBriefsStale(referencing: records, at: now, in: tx)
            try tx.insert(
                AuditEvent(
                    action: "data.deleted", actor: principal, at: now, affected: deleted, outcome: .succeeded,
                    detail: "\(deleted.count) record(s)"))
            return DeletionResult(deleted: deleted, changes: changes, staleBriefs: stale)
        }
        for ref in rawRefs { try raw.delete(RawContentRef(ref)) }
        logger.notice("items deleted", ["count": .count(result.deleted.count)])
        return result
    }

    /// Paired devices may delete what the owner captured or tracks with them, but not preferences.
    static func devicesMayDelete(_ item: DeletableItem, _ principal: Principal) -> Bool {
        guard case .pairedDevice = principal else { return false }
        if case .preference = item { return false }
        return true
    }

    /// Removes deleted evidence from tasks and proposals, which keep their text but lose the link.
    static func unlinkEvidence(_ ids: Set<EvidenceID>, at now: Date, in tx: any RecordWriting) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        var changed = 0
        for task in try tx.find(LisaTask.self, .all) where !ids.isDisjoint(with: task.evidenceIDs) {
            var task = task
            task.evidenceIDs.removeAll { ids.contains($0) }
            task.updatedAt = now
            try tx.update(task)
            changed += 1
        }
        for proposal in try tx.find(EventProposal.self, .all) where !ids.isDisjoint(with: proposal.evidenceIDs) {
            var proposal = proposal
            proposal.evidenceIDs.removeAll { ids.contains($0) }
            proposal.updatedAt = now
            try tx.update(proposal)
            changed += 1
        }
        return changed
    }

    /// Removes items citing a deleted record from stored briefs and marks those briefs stale, so the deleted content
    /// is no longer shown and the current brief is regenerated.
    static func markBriefsStale(referencing records: Set<String>, at now: Date, in tx: any RecordWriting) throws
        -> [BriefID]
    {
        guard !records.isEmpty else { return [] }
        var stale: [BriefID] = []
        let cites: (BriefItem) -> Bool = { item in item.references.contains { records.contains($0.recordID) } }
        for brief in try tx.find(Brief.self, .all) {
            guard (brief.items + brief.omitted).contains(where: cites) else { continue }
            var brief = brief
            brief.items.removeAll(where: cites)
            brief.omitted.removeAll(where: cites)
            brief.text = brief.items.map(\.text).joined(separator: "\n")
            brief.spokenText = brief.items.map(\.spokenText).joined(separator: " ")
            brief.state = .stale
            brief.updatedAt = now
            try tx.update(brief)
            stale.append(brief.id)
        }
        return stale
    }
}
