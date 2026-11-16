// Read-only queries for clients: paged lists, lookups, the day's rundown and brief, and health facts.

import Foundation
import LisaDomain
import LisaPorts
import LisaTime

/// One page of records. `nextCursor` is the last record's identifier when more records follow.
public struct RecordPage<Item: Sendable>: Sendable {
    public var items: [Item]
    public var nextCursor: String?
}

extension LisaApplication {
    /// The largest page any query returns.
    public static let maxPageSize = 200

    /// A page of `type` ordered by identifier, which is stable across inserts.
    public func page<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery = .all, limit: Int, after cursor: String?)
        throws -> RecordPage<E>
    {
        let bounded = max(1, min(limit, Self.maxPageSize))
        var paged = query.sorted(by: "id").limited(to: bounded + 1)
        if let cursor { paged = paged.filter("id", .greaterThan, .text(cursor)) }
        let rows = try store.read { try $0.find(type, paged) }
        let items = Array(rows.prefix(bounded))
        return RecordPage(items: items, nextCursor: rows.count > bounded ? items.last.map { "\($0.id)" } : nil)
    }

    public func record<E: StoredEntity>(_ type: E.Type, id: E.ID) throws -> E? {
        try store.read { try $0.get(type, id: id) }
    }

    public func all<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery = .all) throws -> [E] {
        try store.read { try $0.find(type, query) }
    }

    /// The stored plan for `date`, computed first when none exists for today or a later date.
    public func rundown(for date: LocalDate) throws -> Plan? {
        let owner = try services.settings.currentSettings()
        let key = Plan.key(date: date, zone: owner.zone)
        if let plan = try store.read({ try $0.first(Plan.self, RecordQuery.all.filter("natural_key", equals: key)) }) {
            return plan
        }
        guard date >= ZoneRules.localDate(for: clock.now(), in: owner.zone.timeZone) else { return nil }
        return try services.plans.compute(for: date)
    }

    /// The stored brief for `date`, generated first when none exists for today.
    public func brief(for date: LocalDate) throws -> Brief? {
        let owner = try services.settings.currentSettings()
        let key = Brief.key(date: date, zone: owner.zone)
        if let brief = try store.read({ try $0.first(Brief.self, RecordQuery.all.filter("natural_key", equals: key)) })
        {
            return brief
        }
        guard date == ZoneRules.localDate(for: clock.now(), in: owner.zone.timeZone) else { return nil }
        return try services.briefs.generate(for: date)
    }

    /// Delivery counts by state, for health.
    public func outboxCounts() throws -> [DeliveryState: Int] {
        try store.read { tx in
            var counts: [DeliveryState: Int] = [:]
            for state in DeliveryState.allCases {
                counts[state] = try tx.count(Delivery.self, RecordQuery.all.filter("state", equals: state.rawValue))
            }
            return counts
        }
    }
}
