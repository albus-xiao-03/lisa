// Delivery modes, approved owner email addresses, enablement and retry limits.

/// Delivery settings. External delivery is dry-run until configured (REM-02, CFG-02).
public struct DeliverySettings: Hashable, Codable, Sendable {
    public var emailMode: DeliveryMode
    public var callMode: DeliveryMode
    public var pushMode: DeliveryMode
    public var emailEnabled: Bool
    /// The only addresses Lisa may email. Source content can never add to this list.
    public var approvedEmailAddresses: [String]
    public var maxAttempts: Int
    public var baseBackoffSeconds: Int
    public var maxBackoffSeconds: Int
    public var leaseSeconds: Int

    public init(
        emailMode: DeliveryMode = .dryRun, callMode: DeliveryMode = .dryRun, pushMode: DeliveryMode = .dryRun,
        emailEnabled: Bool = false, approvedEmailAddresses: [String] = [], maxAttempts: Int = 5,
        baseBackoffSeconds: Int = 30, maxBackoffSeconds: Int = 3600, leaseSeconds: Int = 120
    ) {
        self.emailMode = emailMode
        self.callMode = callMode
        self.pushMode = pushMode
        self.emailEnabled = emailEnabled
        self.approvedEmailAddresses = approvedEmailAddresses.map { $0.lowercased() }
        self.maxAttempts = maxAttempts
        self.baseBackoffSeconds = baseBackoffSeconds
        self.maxBackoffSeconds = maxBackoffSeconds
        self.leaseSeconds = leaseSeconds
    }

    /// Whether `address` is an approved owner address.
    public func isApproved(emailAddress address: String) -> Bool {
        approvedEmailAddresses.contains(address.lowercased())
    }
}
