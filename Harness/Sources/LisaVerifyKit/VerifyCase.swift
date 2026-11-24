// A case in the owner-verification catalogue (plan §10.8 "the case model").

/// One case: what it checks, where and how it runs, who runs it, what it needs and what passing means.
public struct VerifyCase: Sendable, Identifiable {
    public let id: VerifyCaseID
    public let title: String
    /// The provider or device pair, for example `GMAIL`, `MI` (Mac–iPhone) or `X1`; nil for host and harness cases.
    public let provider: String?
    /// The interface exercised, for example "Gmail API", "IMAP via Bridge" or "Network framework TLS 1.2 PSK".
    public let interface: String
    public let capability: String
    public let environment: String
    public let modes: [VerifyMode]
    public let requiredResultLevel: VerifyResultLevel
    public let requiredEvidence: [String]
    public let executor: VerifyExecutor
    public let prerequisites: [String]
    /// The gate the case serves (plan §22), for example "Apple clients (G3)".
    public let gate: String
    public let expectedOutcome: String
    /// Steps no test can drive, shown by `lisa-verify guide`, each with its expected observation.
    public let manualSteps: [String]
    /// The owner session that runs it (`X1`–`X7`, `LS-1`–`LS-3`); nil for Claude's fixture cases.
    public let session: String?
    /// Whether two devices each record a result under `<case>@<role>` (plan §10.8 "Paired-device sessions").
    public let paired: Bool

    public var area: String { id.area }

    public init(
        id: VerifyCaseID, title: String, provider: String?, interface: String, capability: String,
        environment: String, modes: [VerifyMode], requiredResultLevel: VerifyResultLevel, requiredEvidence: [String],
        executor: VerifyExecutor, prerequisites: [String], gate: String, expectedOutcome: String,
        manualSteps: [String], session: String?, paired: Bool = false
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.interface = interface
        self.capability = capability
        self.environment = environment
        self.modes = modes
        self.requiredResultLevel = requiredResultLevel
        self.requiredEvidence = requiredEvidence
        self.executor = executor
        self.prerequisites = prerequisites
        self.gate = gate
        self.expectedOutcome = expectedOutcome
        self.manualSteps = manualSteps
        self.session = session
        self.paired = paired
    }
}
