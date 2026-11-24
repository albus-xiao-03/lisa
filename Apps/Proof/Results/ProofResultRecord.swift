// PROOF ONLY — Apps/Proof never ships. One line of `results.jsonl`, one record per case, in the field order plan
// §10.8 "Results" lists: run ID, case ID, commit, harness version, provider and interface, non-secret configuration
// (a digest plus allowlisted fields), platform, device model and OS version, Xcode version, APNs environment and
// profile kind, model ID, assumptions, required evidence, expected result, observed result, result level (§10.1),
// status, executor and exact cause, the action IDs and their outcomes, times, and evidence file names; plus a known
// finding when one applies. The X1 additions after `knownFinding` are the proof's (docs/DECISIONS.md D-54).

struct ProofResultRecord: Codable, Sendable {
    struct Configuration: Codable, Sendable {
        let digest: String
        let fields: [String: String]
    }

    struct Times: Codable, Sendable {
        let wallClockStart: String
        let wallClockEnd: String
        let monotonicStartNanoseconds: UInt64
        let monotonicEndNanoseconds: UInt64
    }

    struct PairSession: Codable, Sendable {
        let baseCaseID: String
        let role: String
        let devices: String
        let condition: String
        /// The session nonce `lisa-verify pair-session` showed on both screens, as the owner entered it.
        let harnessNonce: String
        /// The session codes this device showed (equal on both devices of one TLS session).
        let sessionCodes: [String]
    }

    struct Check: Codable, Sendable {
        let id: String
        let status: ProofStatus
        let observed: String
        let evidenceEntries: Int
    }

    let runID: String
    let caseID: String
    let commit: String
    let harnessVersion: String
    let providerInterface: String
    let configuration: Configuration
    let platform: String
    let deviceModel: String
    let osVersion: String
    let xcodeVersion: String
    let apnsEnvironment: String?
    let profileKind: String?
    let modelID: String?
    let assumptions: [String]
    let requiredEvidence: [String]
    let expectedResult: String
    let observedResult: String
    let resultLevel: String?
    let requiredResultLevel: String
    let status: ProofStatus
    let executor: String
    let cause: String
    let actions: [String]
    let times: Times
    let evidenceFiles: [String]
    let knownFinding: String?
    let design: String?
    let pairSession: PairSession?
    let checks: [Check]
}
