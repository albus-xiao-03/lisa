// R1's `PATCH /v1/preferences` as a legacy conversion (plan §8.12.2, the route table; docs/DECISIONS.md D-74). One
// child per change in request order, `change:<index>`, chained per key. Each change is decided in order under R1's
// rules against R1's records as the earlier changes left them: R1's checks, then the child taken in through the ledger,
// projected into R1's record as one R1 service call, and R1's audit event. The first refusal stops the request: the
// earlier children stay applied, the refused one is `refused` and every later one `not_reached`. This part converts
// the keys an ordinary operation may change, in either scope, and R1's refusals; an administrative key in owner scope,
// which waits for the administrative terminal, and a restricted sibling R1 would apply come with M3-6b's next part and
// fail the conversion until then.

import Foundation
import LisaCoreLedger
import LisaDomain
import LisaOwnerData
import LisaPorts
import LisaSyncProtocol
import LisaTrust

public enum LegacyPreferenceRouteError: Error, Hashable, Sendable {
    /// Owner scope reached an administrative key, which waits for the administrative terminal (M3-6b's next part).
    case awaitsAdministrativeReview(index: Int)
    /// A change R1 would apply to a key that doesn't replicate: a restricted sibling (M3-6b's next part).
    case restrictedSibling(index: Int)
    /// R1's record of the change's key isn't Core's projection, so what the child observes isn't known.
    case recordNotProjected(index: Int)
    /// A child the ledger didn't decide as applied.
    case childNotApplied(index: Int)
}

public enum LegacyPreferenceRoutes {
    /// One change as R1's handler reads it: a value sets the key, `confirm: true` confirms it, anything else deletes
    /// it.
    public enum Action: Hashable, Sendable {
        case set(PreferenceValue, expectedRevision: Int64?)
        case confirm
        case delete
    }

    public struct Change: Hashable, Sendable {
        public let key: String
        public let action: Action

        public init(key: String, action: Action) {
            self.key = key
            self.action = action
        }
    }

    /// R1's refusal of one change, without the caller's text. The API renders it from a template that names the
    /// change's position (§8.12.2 "Error bodies never echo caller input").
    public enum Refusal: Hashable, Sendable {
        /// 400: R1 doesn't support the key.
        case unsupportedKey
        /// 400: R1 refused the value. `reason` is R1's own text, which interpolates no caller text except an unknown
        /// weekday's token.
        case invalidValue(reason: String)
        /// 403: a device set an owner-only key.
        case ownerOnly
        /// 403: someone other than the owner deleted a preference.
        case deletedByOwnerOnly
        /// 403: a principal R1 doesn't let change or confirm preferences.
        case notPermitted
        /// 404: R1 holds no record of the key to confirm or delete.
        case notFound
        /// 409: R1's record isn't at the change's `expectedRevision`.
        case changed(currentRevision: Int64)
    }

    /// What a converted request did: R1's records after it, by key; every child with its disposition; the set digest;
    /// R1's domain changes; and the refusal that stopped it, with the refused change's index.
    public struct Effect: Sendable {
        public let preferences: [Preference]
        public let children: [LegacyChildDisposition]
        public let setDigest: Digest256
        public let changes: [DomainChange]
        public let refusal: Refused?
    }

    public struct Refused: Hashable, Sendable {
        public let index: Int
        public let refusal: Refusal
    }

    /// The discriminator of change `index`.
    public static func discriminator(_ index: Int) -> String { "change:\(index)" }

    /// `PATCH /v1/preferences` after its body checks (1–50 changes), all inside the parent.
    public static func update(
        _ requested: [Change], by principal: Principal, context: LegacyRequestContext, in tx: LegacyTransaction
    ) throws -> Effect {
        let plan = try LegacyChildPlan(
            datasetID: context.datasetID, scope: context.scope, requestID: context.requestID,
            changes: try requested.enumerated().map { try child($0.offset, $0.element) })
        var children: [LegacyChildDisposition] = []
        var changes: [DomainChange] = []
        var refused: Refused?
        for (index, change) in requested.enumerated() {
            let key = PreferenceKey(change.key)
            if let refusal = try check(change, key: key, by: principal, in: tx) {
                refused = Refused(index: index, refusal: refusal)
                children.append(disposition(index, plan, .refused))
                break
            }
            guard PreferenceRules.isPermitted(key) else {
                if principal.mayChangeConsequentialSettings, PreferenceRules.isAdministrative(key) {
                    throw LegacyPreferenceRouteError.awaitsAdministrativeReview(index: index)
                }
                throw LegacyPreferenceRouteError.restrictedSibling(index: index)
            }
            let entity = plan.changes[index].entityID
            guard try tx.preferenceRecordIsProjected(change.key, entity: entity) else {
                throw LegacyPreferenceRouteError.recordNotProjected(index: index)
            }
            let outcome = try tx.intake([try plan.signed(at: index, with: tx.signer)], projecting: false)
            children.append(disposition(index, plan, try applied(outcome, index: index)))
            if case .delete = change.action {
                try tx.projectPreference(entity, force: false)
            } else {
                try tx.projectPreference(entity, force: true)
            }
            try tx.records.insert(audit(change, key: key, by: principal, at: tx.now))
            changes.append(.preferenceChanged(key))
        }
        if let refused {
            for index in (refused.index + 1)..<requested.count {
                children.append(disposition(index, plan, .notReached))
            }
        }
        return Effect(
            preferences: try tx.records.find(Preference.self, RecordQuery.all.sorted(by: "key")), children: children,
            setDigest: plan.setDigest, changes: changes, refusal: refused)
    }

    /// R1's checks of one change, in R1's order (`PreferenceService.set` and `confirm`, `DeletionService.delete`),
    /// against R1's records as the earlier changes left them.
    static func check(_ change: Change, key: PreferenceKey, by principal: Principal, in tx: LegacyTransaction) throws
        -> Refusal?
    {
        let existing = try tx.records.find(Preference.self, RecordQuery.all.filter("key", equals: change.key)).first
        switch change.action {
        case .set(let value, let expectedRevision):
            switch principal {
            case .model, .runtime: return .notPermitted
            case .pairedDevice where key.isConsequential: return .ownerOnly
            default: break
            }
            guard PreferenceRules.supported.contains(key) else { return .unsupportedKey }
            do {
                try PreferenceRules.validate(key, value)
            } catch DomainError.invalidValue(_, let reason) {
                return .invalidValue(reason: reason)
            }
            if let expectedRevision, let existing, existing.revision.value != expectedRevision {
                return .changed(currentRevision: existing.revision.value)
            }
            return nil
        case .confirm:
            var isDevice = false
            if case .pairedDevice = principal { isDevice = true }
            guard principal.mayChangeConsequentialSettings || isDevice else { return .notPermitted }
            return existing == nil ? .notFound : nil
        case .delete:
            guard principal.mayChangeConsequentialSettings else { return .deletedByOwnerOnly }
            return existing == nil ? .notFound : nil
        }
    }

    /// Change `index`'s child: its operation on the key's entity, observed at R1's `expectedRevision` when the change
    /// names one that a projection revision can be (≥ 1). Core resolves what every preference child observes when it
    /// decides it, from R1's record as found (D-74).
    static func child(_ index: Int, _ change: Change) throws -> LegacyChange {
        let payload: PreferenceOperationPayload
        var observedRevision: Int64?
        switch change.action {
        case .set(let value, let expectedRevision):
            payload = .set(key: change.key, value: wire(value))
            if let expectedRevision, expectedRevision >= 1 { observedRevision = expectedRevision }
        case .confirm:
            payload = .confirm(key: change.key)
        case .delete:
            payload = .delete(key: change.key)
        }
        let entity = PreferenceEntity.id(forKey: change.key)
        return LegacyChange(
            discriminator: discriminator(index), entityType: PreferenceEntity.entityType, entityID: entity,
            chain: "preference:" + entity.hex, operationType: payload.operationType,
            payload: try payload.canonicalValue, observedRevision: observedRevision)
    }

    /// R1's value on the wire; a number that isn't finite, which JSON can't carry, travels as its text.
    static func wire(_ value: PreferenceValue) -> PreferenceWireValue {
        value.wire ?? .text(value.description)
    }

    /// R1's audit event for an applied change.
    static func audit(_ change: Change, key: PreferenceKey, by principal: Principal, at now: Date) -> AuditEvent {
        switch change.action {
        case .set:
            AuditEvent(
                action: "preference.set", actor: principal, at: now, affected: [key.rawValue], outcome: .succeeded,
                detail: key.isConsequential ? "consequential" : "ordinary")
        case .confirm:
            AuditEvent(
                action: "preference.confirmed", actor: principal, at: now, affected: [key.rawValue],
                outcome: .succeeded, detail: "")
        case .delete:
            AuditEvent(
                action: "data.deleted", actor: principal, at: now, affected: ["preferences:\(key.rawValue)"],
                outcome: .succeeded, detail: "1 record(s)")
        }
    }

    /// The disposition of a child the ledger took in: applied, with a conflict or not. Anything else fails the
    /// conversion, which then keeps nothing.
    static func applied(_ outcomes: [CoreIntakeOutcome], index: Int) throws -> LegacyChildDisposition.Disposition {
        guard outcomes.count == 1, case .receipted(let signed) = outcomes[0] else {
            throw LegacyPreferenceRouteError.childNotApplied(index: index)
        }
        switch try signed.receipt().outcome {
        case .accepted: return .applied
        case .acceptedWithConflict: return .appliedWithConflict
        case .rejected, .waitingForDependencies: throw LegacyPreferenceRouteError.childNotApplied(index: index)
        }
    }

    static func disposition(
        _ index: Int, _ plan: LegacyChildPlan, _ disposition: LegacyChildDisposition.Disposition
    ) -> LegacyChildDisposition {
        LegacyChildDisposition(
            index: index, childID: plan.childIDs[index], discriminator: discriminator(index), disposition: disposition)
    }
}
