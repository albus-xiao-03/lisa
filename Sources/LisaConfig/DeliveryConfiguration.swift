// The `delivery` section: dry-run or live modes, enablement, the owner's approved contacts, retries and call policy.

import LisaDomain

/// How each external channel delivers: captured by a dry-run transport, or sent for real.
public struct DeliveryModes: Hashable, Sendable {
    /// Email through the SMTP adapter (the `email` section).
    public let email: DeliveryMode
    /// Phone calls through the Twilio adapter (the `calls` section).
    public let call: DeliveryMode
    /// Push notifications through APNs (`notifications.apns`).
    public let push: DeliveryMode
}

/// The call-escalation rule (CALL-01). Every condition is enforced by deterministic code, never by model output.
public struct CallPolicyConfiguration: Hashable, Sendable {
    /// A confirmed deadline within this many minutes may qualify for a call.
    public let urgencyWindowMinutes: Int
    /// Only high- or urgent-priority commitments qualify.
    public let requireHighPriority: Bool
    /// A call needs an earlier reminder that was delivered and not acknowledged.
    public let requireEarlierUnacknowledgedReminder: Bool
    /// The most calls about one commitment in a local day.
    public let maxCallsPerCommitmentPerDay: Int
    /// The most calls in a local day, over all commitments.
    public let maxCallsPerDay: Int
}

/// Delivery settings (REM-02, REM-03, EMAIL-01, CALL-01, CFG-02). Configuration is the only source of the approved
/// addresses and number; nothing is inferred from messages, adapters or other settings.
public struct DeliveryConfiguration: Hashable, Sendable {
    /// Each channel is `dryRun` (deliveries are recorded, never sent) until set to `live`.
    public let modes: DeliveryModes
    /// Whether Lisa may plan email deliveries at all.
    public let emailEnabled: Bool
    /// Whether call escalation is enabled at all.
    public let callsEnabled: Bool
    /// The only addresses Lisa may email, lowercased. They also identify the owner in forwarded mail.
    public let approvedEmailAddresses: [String]
    /// The only number Lisa may call, in E.164 form.
    public let approvedPhoneNumber: String?
    /// Attempts per delivery before it fails.
    public let maxAttempts: Int
    /// The first retry delay; later delays double, with jitter, up to `maxBackoffSeconds`.
    public let baseBackoffSeconds: Int
    /// The longest retry delay.
    public let maxBackoffSeconds: Int
    /// How long a claimed delivery stays leased to one worker.
    public let leaseSeconds: Int
    /// When a call may escalate a reminder.
    public let calls: CallPolicyConfiguration

    /// Everything dry-run, email and calls disabled, no approved contacts; retry and call limits as in R1.
    public static let defaultValue: DeliveryConfiguration = {
        let delivery = DeliverySettings()
        let calls = CallSettings()
        return DeliveryConfiguration(
            modes: DeliveryModes(email: .dryRun, call: .dryRun, push: .dryRun), emailEnabled: false,
            callsEnabled: false, approvedEmailAddresses: [], approvedPhoneNumber: nil,
            maxAttempts: delivery.maxAttempts, baseBackoffSeconds: delivery.baseBackoffSeconds,
            maxBackoffSeconds: delivery.maxBackoffSeconds, leaseSeconds: delivery.leaseSeconds,
            calls: CallPolicyConfiguration(
                urgencyWindowMinutes: calls.urgencyWindowMinutes, requireHighPriority: calls.requireHighPriority,
                requireEarlierUnacknowledgedReminder: calls.requireEarlierUnacknowledgedReminder,
                maxCallsPerCommitmentPerDay: calls.maxCallsPerCommitmentPerDay, maxCallsPerDay: calls.maxCallsPerDay))
    }()

    static func decode(_ section: ConfigSection?) -> DeliveryConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return DeliveryConfiguration(
            modes: decodeModes(section.section("modes"), defaults: defaults.modes),
            emailEnabled: section.bool("emailEnabled", default: defaults.emailEnabled),
            callsEnabled: section.bool("callsEnabled", default: defaults.callsEnabled),
            approvedEmailAddresses: decodeAddresses(section) ?? defaults.approvedEmailAddresses,
            approvedPhoneNumber: section.validated("approvedPhoneNumber", maxLength: 16, Self.phoneNumber),
            maxAttempts: section.integer("maxAttempts", default: defaults.maxAttempts, in: 1...20),
            baseBackoffSeconds: section.integer(
                "baseBackoffSeconds", default: defaults.baseBackoffSeconds, in: 1...3600),
            maxBackoffSeconds: section.integer(
                "maxBackoffSeconds", default: defaults.maxBackoffSeconds, in: 1...86_400),
            leaseSeconds: section.integer("leaseSeconds", default: defaults.leaseSeconds, in: 10...3600),
            calls: decodeCallPolicy(section.section("calls"), defaults: defaults.calls))
    }

    /// An E.164 number such as `+15555550100`.
    static func phoneNumber(_ text: String) -> Result<String, ValueRefusal> {
        ContactFormats.isE164(text)
            ? .success(text)
            : .failure(
                ValueRefusal(
                    "must be a phone number in E.164 form: + and the country code and number, with no spaces",
                    fix: "for example +15555550100"))
    }

    /// A plausible address, lowercased.
    static func emailAddress(_ text: String) -> Result<String, ValueRefusal> {
        ContactFormats.isPlausibleEmailAddress(text)
            ? .success(text.lowercased())
            : .failure(ValueRefusal("must be an email address such as owner@example.com"))
    }

    private static func decodeModes(_ section: ConfigSection?, defaults: DeliveryModes) -> DeliveryModes {
        guard let section else { return defaults }
        defer { section.finish() }
        let options: [DeliveryMode] = [.dryRun, .live]
        return DeliveryModes(
            email: section.choice("email", default: defaults.email, options: options),
            call: section.choice("call", default: defaults.call, options: options),
            push: section.choice("push", default: defaults.push, options: options))
    }

    private static func decodeAddresses(_ section: ConfigSection) -> [String]? {
        guard let entries = section.list("approvedEmailAddresses", maxCount: 20) else { return nil }
        let addresses = entries.map { $0.validated(maxLength: 254, emailAddress) }
        guard addresses.allSatisfy({ $0 != nil }) else { return nil }
        var seen: Set<String> = []
        return addresses.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    private static func decodeCallPolicy(_ section: ConfigSection?, defaults: CallPolicyConfiguration)
        -> CallPolicyConfiguration
    {
        guard let section else { return defaults }
        defer { section.finish() }
        return CallPolicyConfiguration(
            urgencyWindowMinutes: section.integer(
                "urgencyWindowMinutes", default: defaults.urgencyWindowMinutes, in: 1...120),
            requireHighPriority: section.bool("requireHighPriority", default: defaults.requireHighPriority),
            requireEarlierUnacknowledgedReminder: section.bool(
                "requireEarlierUnacknowledgedReminder", default: defaults.requireEarlierUnacknowledgedReminder),
            maxCallsPerCommitmentPerDay: section.integer(
                "maxCallsPerCommitmentPerDay", default: defaults.maxCallsPerCommitmentPerDay, in: 1...10),
            maxCallsPerDay: section.integer("maxCallsPerDay", default: defaults.maxCallsPerDay, in: 1...10))
    }
}
