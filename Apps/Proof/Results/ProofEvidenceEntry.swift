// PROOF ONLY — Apps/Proof never ships. One observation, appended to the run's `evidence.jsonl` the moment it is made
// (so a killed app loses nothing): which case and check it serves, its status, what was observed, this device's
// monotonic time (for measurement) and wall-clock time (for correlation only), and the session, fetch or platform
// report behind it. Results reference this file by name (plan §10.8 "evidence file names").

struct ProofEvidenceEntry: Codable, Sendable {
    let runID: String
    /// The correlated case ID (`<case>@<role>` for paired sessions), or `ProofCellCheck.deviceLevelCaseKey`.
    let caseID: String
    let design: String?
    let check: String
    let status: ProofStatus
    let observed: String
    let monotonicNanoseconds: UInt64
    let wallClock: String
    var session: ProofSessionReport?
    var fetch: ProbeFetchTrace?
    var platform: ProbePlatformFactsReport?
    var details: [String: String] = [:]
}
