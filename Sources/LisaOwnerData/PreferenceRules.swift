// R2's rules for preference keys (docs/DECISIONS.md D-74): which keys R1 supports, which are administrative
// (R2-TRUST-05: R1's consequential keys), which an ordinary synchronized operation may change and so replicate (plan
// §8.17's "permitted preferences"), and R1's own check of a value. R1's `PreferenceMapping` is the authority on keys
// and values; `supported` repeats the keys its mapping handles, every key `PreferenceKey` names.

import LisaDomain

public enum PreferenceRules {
    /// The keys R1's `PreferenceMapping` maps; R1 refuses any other key as "not a supported preference".
    public static let supported: Set<PreferenceKey> = [
        .timeZone, .planningWindows, .protectedTime, .bufferMinutes, .maximumAllocation, .briefTime, .briefLength,
        .briefTopics, .newsInterests, .mutedSources, .mutedTopics, .reminderOffsets, .reminderChannels, .quietHours,
        .callEscalation, .ideaExplorationMinutes, .ideaExplorationFrequency, .approvedEmailAddresses,
        .approvedPhoneNumber, .emailEnabled, .callsEnabled, .timeSensitiveNotifications, .modelEndpoint,
        .modelDataSharing,
    ]

    /// R2-TRUST-05's administrative keys, R1's consequential ones: who is contacted, how, and where private content
    /// goes. Only the administrative terminal changes them.
    public static func isAdministrative(_ key: PreferenceKey) -> Bool {
        key.isConsequential
    }

    /// Whether an ordinary synchronized operation may set, delete or confirm `key`: a supported key that isn't
    /// administrative. Only these keys replicate; the others are restricted (plan §8.12.2, §8.17).
    public static func isPermitted(_ key: PreferenceKey) -> Bool {
        supported.contains(key) && !key.isConsequential
    }

    /// R1's check of `value` for `key`, as `PreferenceService.set` makes it; throws R1's `DomainError.invalidValue`.
    public static func validate(_ key: PreferenceKey, _ value: PreferenceValue) throws {
        try PreferenceService.validate(key, value)
    }
}
