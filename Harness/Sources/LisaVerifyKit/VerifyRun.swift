// A run's record, `run.json` (plan §10.8 "Repeatable and resumable").

/// What a run is: its mode, the commit and harness version it ran from, the cases selected and each case's state,
/// and the real-action confirmations it recorded.
public struct VerifyRun: Codable, Sendable, Equatable {
    public var id: VerifyRunID
    public var mode: VerifyMode
    /// Wall-clock UTC, for correlation only.
    public var createdAt: String
    public var commit: String
    public var harnessVersion: String
    /// The case IDs selected, in order.
    public var selection: [VerifyCaseID]
    public var caseStates: [String: VerifyCaseState]
    /// The digests of the action lists the owner confirmed with `--confirm-real-actions` (live mode).
    public var confirmations: [String]

    public init(
        id: VerifyRunID, mode: VerifyMode, createdAt: String, commit: String, harnessVersion: String,
        selection: [VerifyCaseID], caseStates: [String: VerifyCaseState] = [:], confirmations: [String] = []
    ) {
        self.id = id
        self.mode = mode
        self.createdAt = createdAt
        self.commit = commit
        self.harnessVersion = harnessVersion
        self.selection = selection
        self.caseStates = caseStates
        self.confirmations = confirmations
    }

    public func state(of id: VerifyCaseID) -> VerifyCaseState { caseStates[id.text] ?? .pending }
}
