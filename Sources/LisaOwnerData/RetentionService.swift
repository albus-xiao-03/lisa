// Retention (DATA-05): raw content, delivery history, audit records and feed items are purged by age.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// Retention periods in days. Zero keeps records indefinitely. Logs rotate by size in `LisaLogging`.
public struct RetentionSettings: Hashable, Codable, Sendable {
    public var rawContentDays: Int
    public var deliveryHistoryDays: Int
    public var auditDays: Int
    /// Feed items that were never shared, rated or saved by the owner.
    public var feedItemDays: Int

    public init(rawContentDays: Int = 90, deliveryHistoryDays: Int = 180, auditDays: Int = 365, feedItemDays: Int = 30)
    {
        self.rawContentDays = rawContentDays
        self.deliveryHistoryDays = deliveryHistoryDays
        self.auditDays = auditDays
        self.feedItemDays = feedItemDays
    }
}

/// What one retention pass removed.
public struct RetentionReport: Hashable, Sendable {
    public var rawContent = 0
    public var deliveries = 0
    public var auditEvents = 0
    public var feedItems = 0
}

/// Applies retention periods.
public final class RetentionService: Sendable {
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

    @discardableResult
    public func prune(_ settings: RetentionSettings) throws -> RetentionReport {
        let now = clock.now()
        var report = RetentionReport()
        func cutoff(_ days: Int) -> Date? { days > 0 ? now.addingTimeInterval(-Double(days) * 86_400) : nil }
        if let date = cutoff(settings.rawContentDays) { report.rawContent = try raw.purge(storedBefore: date) }
        var rawRefs: [String] = []
        try store.write { tx in
            if let date = cutoff(settings.deliveryHistoryDays) {
                let old = try tx.find(
                    Delivery.self, RecordQuery.all.filter("next_attempt_at", .lessThan, .instant(date)))
                for delivery in old where delivery.state.isFinal {
                    try tx.delete(Delivery.self, id: delivery.id)
                    report.deliveries += 1
                }
            }
            if let date = cutoff(settings.auditDays) {
                let old = try tx.find(AuditEvent.self, RecordQuery.all.filter("at", .lessThan, .instant(date)))
                for event in old { try tx.delete(AuditEvent.self, id: event.id) }
                report.auditEvents = old.count
            }
            if let date = cutoff(settings.feedItemDays) {
                let old = try tx.find(NewsItem.self, RecordQuery.all.filter("retrieved_at", .lessThan, .instant(date)))
                for item in old where !item.isSharedContent && item.feedback == nil {
                    if let evidence = try tx.get(Evidence.self, id: item.evidenceID) {
                        if let ref = evidence.contentRef { rawRefs.append(ref) }
                        try tx.delete(Evidence.self, id: evidence.id)
                    }
                    try tx.delete(NewsItem.self, id: item.id)
                    report.feedItems += 1
                }
            }
            if report.deliveries + report.auditEvents + report.feedItems + report.rawContent > 0 {
                try tx.insert(
                    AuditEvent(
                        action: "retention.pruned", actor: .runtime, at: now, affected: [], outcome: .succeeded,
                        detail:
                            "raw=\(report.rawContent) deliveries=\(report.deliveries) audit=\(report.auditEvents) feed=\(report.feedItems)"
                    ))
            }
        }
        for ref in rawRefs { try raw.delete(RawContentRef(ref)) }
        logger.info(
            "retention applied",
            [
                "raw": .count(report.rawContent), "deliveries": .count(report.deliveries),
                "audit": .count(report.auditEvents), "feed": .count(report.feedItems),
            ])
        return report
    }
}
