// A preference key's merged state (plan §8.3.1; docs/DECISIONS.md D-73). One multi-value register holds the key's
// writes: a set writes its value and a delete writes none, each replacing exactly the versions it observed. So a delete
// clears what it saw, and a later set re-creates the key, as R1's delete then set does; a key is a register, not an
// owner item, so §8.3.1's dominating tombstone doesn't apply. A confirmation confirms the model-authority candidates it
// observed. Every rule is a join, so the order of application changes nothing.

import LisaSyncProtocol

/// The merged state of one preference key.
public struct PreferenceMergeState: Hashable, Sendable {
    public private(set) var register = MultiValueRegister<PreferenceWireValue?>()
    /// Each confirmation with what it observed and so confirms.
    private var confirmations: [Identifier128: ObservedCoverage] = [:]

    public init() {}

    /// Applies one operation of the key. Applying it again changes nothing.
    public mutating func apply(
        _ payload: PreferenceOperationPayload, id: Identifier128, authority: MergeAuthority = .owner,
        observed: ObservedCoverage, commit: CommitPosition? = nil
    ) {
        switch payload {
        case .set(_, let value):
            register.apply(id: id, value: value, authority: authority, observed: observed, commit: commit)
        case .delete:
            register.apply(id: id, value: nil, authority: authority, observed: observed, commit: commit)
        case .confirm:
            confirmations[id] = observed
        }
    }

    /// Records Core's commit position for an operation applied while pending.
    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        register.markCommitted(id, at: commit)
    }

    public var view: PreferenceView {
        let values = register.values
        let shown = values.first { $0.value != nil }
        let confirmed =
            shown.map { candidate in
                candidate.authority.isProtected
                    || confirmations.values.contains { $0.covers(candidate.id, committedAt: candidate.commit) }
            } ?? false
        return PreferenceView(
            values: values.map(\.value), shownID: shown?.id, confirmed: confirmed,
            suggestions: register.suggestions.compactMap(\.value))
    }
}

/// What a preference key shows after merging.
public struct PreferenceView: Hashable, Sendable {
    /// The surviving writes of the winning authority class in display order; `nil` for a delete.
    public let values: [PreferenceWireValue?]
    /// The write whose value is shown, when any survivor has a value.
    public let shownID: Identifier128?
    /// Whether the shown value takes effect as the owner's: an owner value, or a model value a confirmation observed.
    public let confirmed: Bool
    /// Model and source values kept beside surviving owner values.
    public let suggestions: [PreferenceWireValue]

    /// The value shown: the first surviving value in display order; `nil` when every survivor is a delete.
    public var shown: PreferenceWireValue? { values.compactMap { $0 }.first }

    /// Whether the key holds a value.
    public var exists: Bool { shown != nil }

    /// Two or more surviving writes, a delete among them or not: a conflict for the owner to resolve.
    public var isConflict: Bool { values.count > 1 }
}
