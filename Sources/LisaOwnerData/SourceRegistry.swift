// Source records: registration, enable and disable with an explicit retention choice (DATA-05).

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// What disabling a source did with its imported records.
public struct SourceDisableResult: Sendable {
    public var source: Source
    /// True when previously imported records were kept.
    public var retained: Bool
    public var deletedRecords: Int
}

/// Registers and manages sources.
public final class SourceRegistry: Sendable {
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

    /// The source with `configurationKey`, created if missing.
    public static func ensureSource(
        kind: SourceKind, name: String, configurationKey: String, staleAfterSeconds: Int = 6 * 3600, now: Date,
        in tx: any RecordWriting
    ) throws -> Source {
        if let existing = try tx.first(
            Source.self, RecordQuery.all.filter("configuration_key", equals: configurationKey))
        {
            return existing
        }
        return try tx.insert(
            Source(
                kind: kind, name: name, configurationKey: configurationKey, staleAfterSeconds: staleAfterSeconds,
                now: now))
    }

    /// Registers a configured source, or updates its name and staleness threshold.
    public func register(kind: SourceKind, name: String, configurationKey: String, staleAfterSeconds: Int) throws
        -> Source
    {
        let now = clock.now()
        return try store.write { tx in
            var source = try Self.ensureSource(
                kind: kind, name: name, configurationKey: configurationKey, staleAfterSeconds: staleAfterSeconds,
                now: now, in: tx)
            guard source.name != name || source.staleAfterSeconds != staleAfterSeconds else { return source }
            source.name = name
            source.staleAfterSeconds = staleAfterSeconds
            source.updatedAt = now
            return try tx.update(source)
        }
    }

    public func enable(_ id: SourceID, by principal: Principal) throws -> Source {
        guard principal.mayChangeConsequentialSettings else {
            throw DomainError.notPermitted("only the owner can enable sources")
        }
        let now = clock.now()
        return try store.write { tx in
            var source = try tx.require(Source.self, id: id)
            source.enabled = true
            source.updatedAt = now
            let saved = try tx.update(source)
            try tx.insert(
                AuditEvent(
                    action: "source.enabled", actor: principal, at: now, affected: [id.rawValue], outcome: .succeeded,
                    detail: source.kind.rawValue))
            return saved
        }
    }

    /// Disables a source. With `retainImported` false, the source's imported emails, events, news and evidence and
    /// their raw content are deleted; derived tasks and proposals keep their text but lose the deleted evidence links.
    public func disable(_ id: SourceID, retainImported: Bool, by principal: Principal) throws -> SourceDisableResult {
        guard principal.mayChangeConsequentialSettings else {
            throw DomainError.notPermitted("only the owner can disable sources")
        }
        let now = clock.now()
        var rawRefs: [String] = []
        let result = try store.write { tx -> SourceDisableResult in
            var source = try tx.require(Source.self, id: id)
            source.enabled = false
            source.retainImportedOnDisable = retainImported
            source.cursor = retainImported ? source.cursor : nil
            source.updatedAt = now
            var deleted = 0
            if !retainImported {
                let bySource = RecordQuery.all.filter("source_id", equals: id.rawValue)
                let evidence = try tx.find(Evidence.self, bySource)
                rawRefs = evidence.compactMap(\.contentRef)
                deleted += try Self.deleteAll(EmailMessage.self, bySource, in: tx)
                deleted += try Self.deleteAll(CalendarOccurrence.self, bySource, in: tx)
                deleted += try Self.deleteAll(NewsItem.self, bySource, in: tx)
                deleted += try DeletionService.unlinkEvidence(Set(evidence.map(\.id)), at: now, in: tx)
                for item in evidence { try tx.delete(Evidence.self, id: item.id) }
                deleted += evidence.count
            }
            let saved = try tx.update(source)
            try tx.insert(
                AuditEvent(
                    action: "source.disabled", actor: principal, at: now, affected: [id.rawValue], outcome: .succeeded,
                    detail: retainImported ? "imported records retained" : "imported records deleted (\(deleted))"))
            return SourceDisableResult(source: saved, retained: retainImported, deletedRecords: deleted)
        }
        for ref in rawRefs { try raw.delete(RawContentRef(ref)) }
        logger.notice(
            "source disabled",
            [
                "source": .public(id.rawValue), "retained": .public(retainImported ? "yes" : "no"),
                "deleted": .count(result.deletedRecords),
            ])
        return result
    }

    static func deleteAll<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery, in tx: any RecordWriting) throws -> Int
    {
        let records = try tx.find(type, query)
        for record in records { try tx.delete(type, id: record.id) }
        return records.count
    }
}
