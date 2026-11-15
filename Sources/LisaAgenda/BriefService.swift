// The daily brief (BRIEF-01–BRIEF-04): composition from stored data, versions, scheduled delivery and catch-up.

import Foundation
import LisaBriefComposer
import LisaDelivery
import LisaDomain
import LisaLogging
import LisaPolicy
import LisaPorts
import LisaRanking
import LisaTime

/// Builds and dispatches briefs. One brief record exists per local date and timezone; regeneration creates a new
/// version of it. A failed regeneration keeps the last good content and records the failure.
public final class BriefService: Sendable {
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let settings: any SettingsSource
    private let notifications: NotificationService
    private let outbox: DeliveryOutbox

    public init(
        store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource,
        notifications: NotificationService, outbox: DeliveryOutbox
    ) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
        self.notifications = notifications
        self.outbox = outbox
    }

    /// Composes the brief for `date` and stores it as the next version.
    @discardableResult
    public func generate(for date: LocalDate) throws -> Brief {
        do {
            return try compose(date)
        } catch let error as StoreError {
            if case .conflict = error { return try compose(date) }
            try recordFailure(date, reason: error.description)
            throw error
        } catch {
            try recordFailure(date, reason: "the brief could not be generated")
            throw error
        }
    }

    func compose(_ date: LocalDate) throws -> Brief {
        let owner = try settings.currentSettings()
        let now = clock.now()
        return try store.write { tx in
            let input = try Self.input(date: date, owner: owner, now: now, in: tx)
            let composed = BriefComposer.compose(input)
            let key = Brief.key(date: date, zone: owner.zone)
            if var brief = try tx.first(Brief.self, RecordQuery.all.filter("natural_key", equals: key)) {
                brief.version += 1
                brief.text = composed.text
                brief.spokenText = composed.spokenText
                brief.items = composed.items
                brief.omitted = composed.omitted
                brief.state = .current
                brief.generatedAt = now
                brief.estimatedSpokenSeconds = composed.estimatedSpokenSeconds
                brief.templateOnly = true
                brief.lastFailure = nil
                brief.updatedAt = now
                return try tx.update(brief)
            }
            return try tx.insert(
                Brief(
                    localDate: date, zone: owner.zone, version: 1, text: composed.text, spokenText: composed.spokenText,
                    items: composed.items, omitted: composed.omitted, generatedAt: now,
                    estimatedSpokenSeconds: composed.estimatedSpokenSeconds, templateOnly: true))
        }
    }

    func recordFailure(_ date: LocalDate, reason: String) throws {
        let owner = try settings.currentSettings()
        let now = clock.now()
        try store.write { tx in
            guard
                var brief = try tx.first(
                    Brief.self, RecordQuery.all.filter("natural_key", equals: Brief.key(date: date, zone: owner.zone)))
            else { return }
            brief.state = .failed
            brief.lastFailure = reason
            brief.updatedAt = now
            try tx.update(brief)
        }
        logger.warning("brief generation failed; the previous version is kept", ["date": .public(date.iso)])
    }

    /// The composer input, gathered from stored records only.
    static func input(date: LocalDate, owner: OwnerSettings, now: Date, in tx: any RecordReading) throws -> BriefInput {
        let zone = owner.zone.timeZone
        let day = ZoneRules.dayRange(date, in: zone)
        let commitments = try tx.find(
            CalendarOccurrence.self,
            RecordQuery.all.filter("start_at", .lessThan, .instant(day.end)).filter(
                "end_at", .greaterThan, .instant(day.start)
            ).sorted(by: "start_at")
        ).filter { $0.status != .cancelled }
        let active = try tx.find(
            LisaTask.self,
            RecordQuery.all.filter("status", in: [TaskStatus.open, .inProgress, .blocked].map { .text($0.rawValue) }))
        let recent = now.addingTimeInterval(-36 * 3600)
        let emails = try tx.find(
            EmailMessage.self, RecordQuery.all.filter("received_at", .greaterOrEqual, .instant(recent))
        )
        .compactMap { email in email.attention?.first.map { EmailAttention(email: email, reason: $0) } }
        let proposals = try tx.find(EventProposal.self, .all).filter { $0.matchState.isUnresolved }
        let plan = try tx.first(
            Plan.self, RecordQuery.all.filter("natural_key", equals: Plan.key(date: date, zone: owner.zone)))
        let sources = try tx.find(Source.self, .all)
        let sourceNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let muted = Set(
            sources.filter { owner.mutedSources.contains($0.name) || owner.mutedSources.contains($0.id.rawValue) }.map(
                \.id))
        let newsCandidates = try tx.find(
            NewsItem.self,
            RecordQuery.all.filter("retrieved_at", .greaterOrEqual, .instant(now.addingTimeInterval(-48 * 3600))))
        let ranked = NewsRanker.rank(
            newsCandidates,
            signals: RankingSignals(
                interests: owner.newsInterests + owner.brief.topics, mutedSources: muted,
                mutedTopics: Set(owner.mutedTopics)),
            now: now, limit: 8)
        let changed = try tx.find(
            CalendarOccurrence.self,
            RecordQuery.all.filter("start_at", .greaterOrEqual, .instant(day.start)).filter(
                "start_at", .lessThan, .instant(day.end.addingTimeInterval(7 * 86_400)))
        )
        .filter { $0.changeSequence > 0 && $0.updatedAt >= now.addingTimeInterval(-24 * 3600) }
        var changes = changed.map { occurrence in
            let what = occurrence.status == .cancelled ? "was cancelled" : "changed"
            return BriefChange(
                text: "\(occurrence.title) \(what).", spokenText: "\(occurrence.title) \(what).",
                references: [SourceReference(recordKind: "occurrence", recordID: occurrence.id.rawValue)])
        }
        if let plan {
            changes += plan.changes.prefix(3).map {
                BriefChange(
                    text: $0, spokenText: $0,
                    references: [SourceReference(recordKind: "plan", recordID: plan.id.rawValue)])
            }
        }
        return BriefInput(
            date: date, zone: owner.zone, now: now, commitments: commitments,
            tasks: active.filter { $0.confirmation == .confirmed },
            possibleTasks: active.filter { $0.confirmation == .possible }, emails: emails, proposals: proposals,
            ideaBlocks: plan?.blocks.filter { $0.kind == .idea } ?? [],
            news: ranked.map {
                BriefNews(item: $0.item, reason: $0.reason, sourceName: sourceNames[$0.item.sourceID] ?? "source")
            },
            changes: changes,
            sources: sources.filter(\.enabled).map { source in
                let freshness = source.freshness(at: now)
                return SourceStatusLine(
                    sourceID: source.id, name: source.name, kind: source.kind, checked: freshness == .fresh,
                    detail: source.isFailing
                        ? source.lastFailure?.summary : (freshness == .fresh ? nil : "not refreshed recently"))
            },
            availabilityUncertain: plan?.basis.availabilityUncertain ?? false, settings: owner.brief)
    }

    /// At or after the configured brief time, generates today's brief and dispatches it once: email to approved
    /// addresses (when enabled) and one availability notification. After downtime it catches up only within the
    /// configured window; beyond it, the skip is recorded instead.
    @discardableResult
    public func dispatchIfDue() throws -> Brief? {
        let owner = try settings.currentSettings()
        let zone = owner.zone.timeZone
        let now = clock.now()
        let today = ZoneRules.localDate(for: now, in: zone)
        let scheduledAt = ZoneRules.instant(for: LocalDateTime(date: today, time: owner.brief.deliveryTime), in: zone)
        guard now >= scheduledAt else { return nil }
        let marker = NotificationService.briefOccurrenceKey(date: today, zone: owner.zone)
        let handled = try store.read { tx in
            try tx.first(NotificationIntent.self, RecordQuery.all.filter("occurrence_key", equals: marker)) != nil
        }
        guard !handled else { return nil }
        let brief = try generate(for: today)
        let allowed = RecoveryPolicy.allowsCatchUpBrief(
            scheduledAt: scheduledAt, now: now, windowHours: owner.brief.catchUpWindowHours, alreadyDelivered: false)
        try store.write { tx in
            if allowed {
                try notifications.briefAvailable(brief, settings: owner, in: tx)
                guard owner.delivery.emailEnabled else { return }
                let endOfDay = ZoneRules.startOfDay(today.adding(days: 1), in: zone)
                for address in owner.delivery.approvedEmailAddresses {
                    try DeliveryOutbox.enqueue(
                        Delivery(
                            channel: .email, recipient: .emailAddress(address), payload: .brief(brief.id),
                            idempotencyKey: "brief-email:\(marker):\(address.lowercased())",
                            mode: outbox.mode(for: .email, settings: owner.delivery), notBefore: now,
                            validUntil: endOfDay, now: now),
                        in: tx)
                }
            } else {
                var silent = owner
                silent.notifications.enabled = false
                if var intent = try notifications.briefAvailable(brief, settings: silent, in: tx) {
                    intent.state = .expired
                    intent.updatedAt = now
                    try tx.update(intent)
                }
                try tx.insert(
                    AuditEvent(
                        action: "brief.catch-up-skipped", actor: .runtime, at: now, affected: [brief.id.rawValue],
                        outcome: .skipped,
                        detail: "the brief time passed more than \(owner.brief.catchUpWindowHours) hours ago"))
            }
        }
        return brief
    }
}
