// The projection of a preference key's merge state into R1's `preferences` record (plan §8.4.1 step 5; docs/
// DECISIONS.md D-73), which R1's API, planner and delivery read. The shown value becomes the record's value: an owner's
// value is `explicit`, a model's `inferred`, and `confirmed` follows the view. A key with no value left has its record
// removed. An existing record changes only when something differs, unless `force` writes it anyway, as R1's `set` and
// `confirm` always write, so one R1 service call is one revision step.

import Foundation
import LisaDomain
import LisaMerge
import LisaPorts
import LisaSyncProtocol

enum PreferenceProjection {
    /// Writes `view` into R1's record of `key` and returns the revision written, if any.
    static func project(
        _ view: PreferenceView?, key: String, commitTime: Date, into records: any RecordWriting, force: Bool = false
    ) throws -> Int64? {
        let existing = try records.find(Preference.self, RecordQuery.all.filter("key", equals: key)).first
        guard let view, let shown = view.shown, let value = PreferenceValue(wire: shown) else {
            if let existing { try records.delete(Preference.self, id: existing.id) }
            return nil
        }
        let origin: PreferenceOrigin = view.shownAuthority?.isProtected == false ? .inferred : .explicit
        guard var record = existing else {
            var record = Preference(key: PreferenceKey(key), value: value, origin: origin, now: commitTime)
            record.confirmed = view.confirmed
            return try records.insert(record).revision.value
        }
        let changed = record.value != value || record.origin != origin || record.confirmed != view.confirmed
        guard changed || force else { return nil }
        record.value = value
        record.origin = origin
        record.confirmed = view.confirmed
        record.updatedAt = commitTime
        return try records.update(record).revision.value
    }
}

extension PreferenceValue {
    /// R1's value for a wire value; `nil` for a number that doesn't read back.
    init?(wire: PreferenceWireValue) {
        switch wire {
        case .text(let text): self = .text(text)
        case .number(let text):
            guard let number = Double(text) else { return nil }
            self = .number(number)
        case .flag(let flag): self = .flag(flag)
        case .list(let items): self = .list(items)
        }
    }

    /// The wire value of R1's value; `nil` for a number that isn't finite.
    public var wire: PreferenceWireValue? {
        switch self {
        case .text(let text): .text(text)
        case .number(let number): .number(number)
        case .flag(let flag): .flag(flag)
        case .list(let items): .list(items)
        }
    }
}
