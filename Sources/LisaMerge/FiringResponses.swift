// The owner's responses to one reminder firing (plan §8.3.1, §8.10.1): an acknowledgement or dismissal suppresses the
// firing, and a concurrent snooze stays in history without creating a new firing; concurrent snoozes take the latest
// instant, capped at the policy maximum, and create one new firing. No clock decides between devices: the instants
// compared are the snoozes' own targets.

import LisaSyncProtocol

/// The merged responses to one firing.
public struct FiringResponses: Hashable, Sendable {
    private var snoozes: [Identifier128: Int64] = [:]
    private var settled: Set<Identifier128> = []

    public init() {}

    /// A snooze until `untilEpochMilliseconds`.
    public mutating func snooze(id: Identifier128, untilEpochMilliseconds: Int64) {
        if snoozes[id] == nil { snoozes[id] = untilEpochMilliseconds }
    }

    /// An acknowledgement or dismissal.
    public mutating func settle(id: Identifier128) {
        settled.insert(id)
    }

    /// Whether the firing is suppressed.
    public var isSuppressed: Bool { !settled.isEmpty }

    /// The one new firing's instant: the latest snooze, capped at `maximum`; nil if suppressed or never snoozed.
    public func nextFiring(cappedAt maximum: Int64) -> Int64? {
        guard !isSuppressed, let latest = snoozes.values.max() else { return nil }
        return min(latest, maximum)
    }

    /// Every snooze, kept in history even when suppressed.
    public var snoozeHistory: [Identifier128: Int64] { snoozes }
}
