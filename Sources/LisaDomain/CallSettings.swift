// Phone-call escalation settings (CALL-01); calls stay disabled until explicitly enabled.

/// Call escalation policy. Every condition is enforced by deterministic code, never by model output.
public struct CallSettings: Hashable, Codable, Sendable {
    public var enabled: Bool
    /// The single approved owner number in E.164 form.
    public var approvedNumber: String?
    /// A confirmed high-priority deadline within this many minutes may qualify.
    public var urgencyWindowMinutes: Int
    public var requireHighPriority: Bool
    public var requireEarlierUnacknowledgedReminder: Bool
    public var maxCallsPerCommitmentPerDay: Int
    public var maxCallsPerDay: Int

    public init(
        enabled: Bool = false, approvedNumber: String? = nil, urgencyWindowMinutes: Int = 15,
        requireHighPriority: Bool = true, requireEarlierUnacknowledgedReminder: Bool = true,
        maxCallsPerCommitmentPerDay: Int = 1, maxCallsPerDay: Int = 3
    ) {
        self.enabled = enabled
        self.approvedNumber = approvedNumber
        self.urgencyWindowMinutes = urgencyWindowMinutes
        self.requireHighPriority = requireHighPriority
        self.requireEarlierUnacknowledgedReminder = requireEarlierUnacknowledgedReminder
        self.maxCallsPerCommitmentPerDay = maxCallsPerCommitmentPerDay
        self.maxCallsPerDay = maxCallsPerDay
    }
}
