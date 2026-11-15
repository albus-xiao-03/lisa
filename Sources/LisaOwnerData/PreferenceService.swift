// Preferences (MEM-01): explicit and inferred values, owner-only consequential keys, and the effective settings.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// Inspects, edits and deletes preferences. Inference may only propose non-consequential values, which take effect
/// after the owner confirms them; an explicit value is never replaced by an inferred one.
public final class PreferenceService: Sendable {
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    public func list() throws -> [Preference] {
        try store.read { try $0.find(Preference.self, RecordQuery.all.sorted(by: "key")) }
    }

    /// Sets an explicit preference. Consequential keys can be changed only by the owner on the host.
    public func set(
        _ key: PreferenceKey, _ value: PreferenceValue, expectedRevision: Revision?, by principal: Principal
    )
        throws -> (Preference, DomainChange)
    {
        switch principal {
        case .model, .runtime: throw DomainError.notPermitted("preferences are set only by the owner")
        case .pairedDevice where key.isConsequential:
            throw DomainError.notPermitted("\(key.rawValue) can only be changed by the owner on the host")
        default: break
        }
        try Self.validate(key, value)
        let now = clock.now()
        let saved = try store.write { tx -> Preference in
            let existing = try tx.first(Preference.self, RecordQuery.all.filter("key", equals: key.rawValue))
            if let expectedRevision, let existing, existing.revision != expectedRevision {
                throw StoreError.conflict(
                    collection: Preference.collectionName, id: key.rawValue, expected: expectedRevision,
                    actual: existing.revision)
            }
            let stored: Preference
            if var existing {
                existing.value = value
                existing.origin = .explicit
                existing.confirmed = true
                existing.updatedAt = now
                stored = try tx.update(existing)
            } else {
                var preference = Preference(key: key, value: value, origin: .explicit, now: now)
                preference.confirmed = true
                stored = try tx.insert(preference)
            }
            try tx.insert(
                AuditEvent(
                    action: "preference.set", actor: principal, at: now, affected: [key.rawValue], outcome: .succeeded,
                    detail: key.isConsequential ? "consequential" : "ordinary"))
            return stored
        }
        logger.info("preference set", ["key": .public(key.rawValue)])
        return (saved, .preferenceChanged(key))
    }

    /// Records a preference inferred from evidence. Consequential keys are refused, and an existing explicit value
    /// is left untouched. The inferred value takes effect only after the owner confirms it.
    public func infer(_ key: PreferenceKey, _ value: PreferenceValue, evidence: [EvidenceID]) throws -> Preference? {
        guard !key.isConsequential else {
            throw DomainError.notPermitted("inference cannot change \(key.rawValue)")
        }
        try Self.validate(key, value)
        let now = clock.now()
        return try store.write { tx in
            if let existing = try tx.first(Preference.self, RecordQuery.all.filter("key", equals: key.rawValue)) {
                guard existing.origin == .inferred, !existing.confirmed else { return nil }
                var updated = existing
                updated.value = value
                updated.evidenceIDs = evidence
                updated.updatedAt = now
                return try tx.update(updated)
            }
            let preference = try tx.insert(
                Preference(key: key, value: value, origin: .inferred, evidenceIDs: evidence, now: now))
            try tx.insert(
                AuditEvent(
                    action: "preference.inferred", actor: .model, at: now, affected: [key.rawValue],
                    outcome: .succeeded,
                    detail: "awaiting confirmation"))
            return preference
        }
    }

    /// Confirms an inferred preference so it takes effect.
    public func confirm(_ key: PreferenceKey, by principal: Principal) throws -> (Preference, DomainChange) {
        guard principal.mayChangeConsequentialSettings || principal.isPairedDevice else {
            throw DomainError.notPermitted("only the owner can confirm preferences")
        }
        let now = clock.now()
        let saved = try store.write { tx -> Preference in
            guard var preference = try tx.first(Preference.self, RecordQuery.all.filter("key", equals: key.rawValue))
            else { throw StoreError.notFound(collection: Preference.collectionName, id: key.rawValue) }
            preference.confirmed = true
            preference.updatedAt = now
            let stored = try tx.update(preference)
            try tx.insert(
                AuditEvent(
                    action: "preference.confirmed", actor: principal, at: now, affected: [key.rawValue],
                    outcome: .succeeded, detail: ""))
            return stored
        }
        return (saved, .preferenceChanged(key))
    }

    /// The effective value of a key that configures the host (for example the model endpoint), if any.
    public func effectiveValue(_ key: PreferenceKey) throws -> PreferenceValue? {
        try store.read { tx in
            try tx.first(Preference.self, RecordQuery.all.filter("key", equals: key.rawValue))
        }.flatMap { $0.isEffective ? $0.value : nil }
    }

    static func validate(_ key: PreferenceKey, _ value: PreferenceValue) throws {
        var scratch = OwnerSettings(zone: .utc)
        try PreferenceMapping.apply(key, value, to: &scratch)
    }
}

/// Configuration overlaid with effective preferences; the `SettingsSource` every service reads.
public final class EffectiveSettings: SettingsSource {
    private let base: @Sendable () throws -> OwnerSettings
    private let store: any RecordStore
    private let logger: Logger

    /// `base` returns the settings from the validated configuration file.
    public init(base: @escaping @Sendable () throws -> OwnerSettings, store: any RecordStore, logger: Logger) {
        self.base = base
        self.store = store
        self.logger = logger
    }

    public func currentSettings() throws -> OwnerSettings {
        var settings = try base()
        let preferences = try store.read { try $0.find(Preference.self, RecordQuery.all.sorted(by: "key")) }
        // The exploration frequency depends on the exploration duration, so it is applied last.
        let ordered = preferences.filter(\.isEffective).sorted { lhs, rhs in
            (lhs.key == .ideaExplorationFrequency ? 1 : 0, lhs.key) < (
                rhs.key == .ideaExplorationFrequency ? 1 : 0, rhs.key
            )
        }
        for preference in ordered {
            do {
                try PreferenceMapping.apply(preference.key, preference.value, to: &settings)
            } catch {
                logger.warning("ignored an invalid stored preference", ["key": .public(preference.key.rawValue)])
            }
        }
        return settings
    }
}

extension Principal {
    var isPairedDevice: Bool {
        if case .pairedDevice = self { true } else { false }
    }
}
