// Extraction over stored emails (MAIL-02, EVENT-01, MODEL-03/04): validated items become tasks, proposals or notes.

import Foundation
import LisaDomain
import LisaInference
import LisaLogging
import LisaPorts
import LisaTime

/// What one review pass did.
public struct ReviewReport: Hashable, Sendable {
    public var processed = 0
    public var tasksCreated = 0
    public var tasksUpdated = 0
    public var proposalsCreated = 0
    public var attentionMarked = 0
    public var awaitingModel = 0
    public var failed = 0
    public var changes: [DomainChange] = []

    public init() {}
}

/// Interprets pending emails. Untrusted content is passed to the model only inside the pipeline's envelope; the
/// result is validated before anything is stored, and owner corrections are never overwritten.
public final class ExtractionService: Sendable {
    public static let maxAttentionNotes = 5
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let settings: any SettingsSource
    private let pipeline: ExtractionPipeline

    public init(
        store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource,
        pipeline: ExtractionPipeline
    ) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
        self.pipeline = pipeline
    }

    /// Reviews up to `limit` emails that are pending or waiting for a model, oldest first.
    public func reviewPending(limit: Int = 20) async throws -> ReviewReport {
        let owner = try settings.currentSettings()
        let pending = try store.read { tx in
            try tx.find(
                EmailMessage.self,
                RecordQuery.all.filter(
                    "extraction",
                    in: [.text(ExtractionState.pending.rawValue), .text(ExtractionState.awaitingModel.rawValue)]
                ).sorted(by: "received_at").limited(to: limit))
        }
        var report = ReviewReport()
        for email in pending {
            let request = ExtractionRequest(
                sourceKind: "email", subject: email.subject, text: email.bodyText, ownerAuthoredText: email.ownerNote,
                addressing: email.addressing, referenceInstant: email.receivedAt, zone: owner.zone.timeZone,
                dateReading: owner.dateReading)
            let outcome = await pipeline.extract(request)
            try apply(outcome, to: email, zone: owner.zone, report: &report)
            report.processed += 1
        }
        if report.processed > 0 {
            logger.info(
                "review pass",
                [
                    "processed": .count(report.processed), "tasks": .count(report.tasksCreated),
                    "proposals": .count(report.proposalsCreated), "awaiting": .count(report.awaitingModel),
                ])
        }
        return report
    }

    func apply(_ outcome: ExtractionOutcome, to email: EmailMessage, zone: TimeZoneID, report: inout ReviewReport)
        throws
    {
        let now = clock.now()
        var local = report
        try store.write { tx in
            guard var current = try tx.get(EmailMessage.self, id: email.id) else { return }
            switch outcome {
            case .awaitingModel(let reason):
                current.extraction = .awaitingModel
                local.awaitingModel += 1
                try tx.insert(Self.audit(current, .skipped, "awaiting model: \(reason)", now))
            case .failed(let reason):
                current.extraction = .failed
                local.failed += 1
                try tx.insert(Self.audit(current, .failed, reason, now))
            case .extracted(let extraction):
                var attention: [String] = []
                for item in extraction.items {
                    switch item.kind {
                    case .commitment, .request:
                        if item.addressedToOwner {
                            let (task, created) = try Self.upsertTask(
                                item, email: current, zone: zone, now: now, in: tx)
                            if created {
                                local.tasksCreated += 1
                                local.changes.append(.taskCreated(task.id))
                            } else {
                                local.tasksUpdated += 1
                                local.changes.append(.taskChanged(task.id, material: false))
                            }
                        }
                        if item.kind == .request {
                            attention.append(
                                item.addressedToOwner
                                    ? "asks you to respond: \(item.title)"
                                    : "contains a request for someone else: \(item.title)")
                        }
                    case .meeting:
                        let proposal = try tx.insert(Self.proposal(item, email: current, zone: zone, now: now))
                        local.proposalsCreated += 1
                        local.changes.append(.proposalChanged(proposal.id))
                    case .change:
                        attention.append("reports a change: \(item.title)")
                    case .information:
                        attention.append(item.title)
                    }
                }
                current.extraction = .extracted
                current.attention = attention.isEmpty ? nil : Array(attention.prefix(Self.maxAttentionNotes))
                if !attention.isEmpty { local.attentionMarked += 1 }
                try tx.insert(
                    Self.audit(
                        current, .succeeded,
                        "provider=\(extraction.provider.name) items=\(extraction.items.count) rejected=\(extraction.rejected.count)",
                        now))
            }
            current.updatedAt = now
            try tx.update(current)
        }
        report = local
    }

    /// Creates a task from an item, or updates the task previously extracted from the same evidence with the same
    /// title. The title compared is the one the extraction gave the task, so a task the owner renamed is still
    /// recognized (DATA-04, D-33). Fields the owner corrected are never changed.
    static func upsertTask(
        _ item: ValidatedItem, email: EmailMessage, zone: TimeZoneID, now: Date, in tx: any RecordWriting
    )
        throws -> (LisaTask, Bool)
    {
        let (deadline, unresolved) = Self.deadline(item.deadline, zone: zone)
        let title = String(item.title.prefix(200))
        let existing = try tx.find(
            LisaTask.self, RecordQuery.all.filter("origin", equals: TaskOrigin.extracted.rawValue)
        )
        .first {
            $0.evidenceIDs.contains(email.evidenceID)
                && ($0.extractedTitle ?? $0.title).lowercased() == title.lowercased()
        }
        if var task = existing {
            // A task stored before extracted titles were kept was matched by its current title, which is the
            // extraction's own; record it so a later rename is recognized too.
            if task.extractedTitle == nil { task.extractedTitle = title }
            var material = false
            if !task.ownerCorrected.contains(.deadline), task.deadline != deadline {
                task.deadline = deadline
                task.unresolvedDeadlineText = unresolved
                material = true
            }
            if !task.ownerCorrected.contains(.priority), task.priority != item.priority {
                task.priority = item.priority
                material = true
            }
            if !task.ownerCorrected.contains(.duration), let minutes = item.durationMinutes {
                task.estimatedMinutes = minutes
            }
            if !task.ownerCorrected.contains(.confirmation), task.confirmation != item.confirmation {
                task.confirmation = item.confirmation
                material = true
            }
            if material { task.changeSequence += 1 }
            task.updatedAt = now
            return (try tx.update(task), false)
        }
        var task = LisaTask(
            title: title, notes: item.notes.joined(separator: "\n"), priority: item.priority,
            deadline: deadline, estimatedMinutes: item.durationMinutes, confirmation: item.confirmation,
            origin: .extracted, evidenceIDs: [email.evidenceID], now: now)
        task.unresolvedDeadlineText = unresolved
        task.extractedTitle = title
        return (try tx.insert(task), true)
    }

    static func deadline(_ when: ResolvedWhen?, zone: TimeZoneID) -> (Deadline?, String?) {
        switch when {
        case .instant(let instant): (.at(instant: instant, zone: zone), nil)
        case .date(let date): (.onDate(date), nil)
        case .unresolved(let text, _): (nil, text)
        case nil: (nil, nil)
        }
    }

    static func proposal(_ item: ValidatedItem, email: EmailMessage, zone: TimeZoneID, now: Date) -> EventProposal {
        var uncertainty = item.notes
        let timing: ProposedTiming
        switch item.start {
        case .instant(let start):
            var end: Date?
            if case .instant(let value) = item.end { end = value }
            if end == nil, let minutes = item.durationMinutes { end = start.addingTimeInterval(Double(minutes) * 60) }
            timing = .timed(start: start, end: end, zone: zone)
        case .date(let date):
            timing = .dateOnly(date)
        case .unresolved(let text, _):
            timing = .unknown
            uncertainty.append("the date \"\(text)\" could not be resolved")
        case nil:
            timing = .unknown
            uncertainty.append("no date was given")
        }
        if item.confirmation != .confirmed { uncertainty.append("the event is not confirmed") }
        return EventProposal(
            title: String(item.title.prefix(200)), timing: timing, location: item.location,
            participants: Array(item.participants.prefix(20)), evidenceIDs: [email.evidenceID],
            uncertainty: Array(uncertainty.prefix(5)), now: now)
    }

    static func audit(_ email: EmailMessage, _ outcome: AuditOutcome, _ detail: String, _ now: Date) -> AuditEvent {
        AuditEvent(
            action: "review.extraction", actor: .model, at: now, affected: [email.id.rawValue], outcome: outcome,
            detail: String(detail.prefix(300)))
    }
}
