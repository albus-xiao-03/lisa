// PROOF ONLY — Apps/Proof never ships. Builds the one `results.jsonl` record of a case from its evidence (plan
// §10.8): for a nearby cell, each required N-1 check takes its latest entry's status; the cell passes only if every
// required check passed (Design A's forward-secret suite included), fails if one failed, and otherwise stays
// NOT_RUN_ENVIRONMENT naming what was not yet observed. Executor is always the owner; required level owner-verified.

import Foundation
import LisaCrypto

@MainActor
enum ProofCellAggregator {
    static let requiredLevel = "owner-verified"

    static func nearbyRecord(
        design: ProofDesign, configuration: ProofNearbyConfiguration, context: ProofRunContext,
        evidence: [ProofEvidenceEntry], startedAt: (wall: String, monotonic: UInt64)
    ) -> ProofResultRecord {
        let cell = evidence.filter { $0.caseID == context.correlatedCaseID && $0.design == design.rawValue }
        let device = evidence.filter { $0.caseID == ProofCellCheck.deviceLevelCaseKey }
        var checks: [ProofResultRecord.Check] = []
        for check in ProofCellCheck.allCases where check != .forwardSecretSuite || design == .a {
            let matching = (check.isDeviceLevel ? device : cell).filter { $0.check == check.rawValue }
            checks.append(
                ProofResultRecord.Check(
                    id: check.rawValue, status: matching.last?.status ?? .notRunEnvironment,
                    observed: matching.last?.observed ?? "not yet observed", evidenceEntries: matching.count))
        }
        let required = Set(ProofCellCheck.required(for: design).map(\.rawValue))
        let decisive = checks.filter { required.contains($0.id) }
        let failed = decisive.filter { $0.status == .fail }.map(\.id)
        let missing = decisive.filter { $0.status != .pass && $0.status != .fail }.map(\.id)
        let status: ProofStatus = !failed.isEmpty ? .fail : (missing.isEmpty ? .pass : .notRunEnvironment)
        let cause =
            switch status {
            case .pass: "every required N-1 check passed on this device"
            case .fail: "failed: \(failed.joined(separator: ", "))"
            default: "pending owner session: not yet observed \(missing.joined(separator: ", "))"
            }
        let codes = Array(Set(cell.compactMap { $0.session?.sessionCode })).sorted()
        return record(
            caseID: context.correlatedCaseID, context: context, configuration: configuration.allowlisted,
            providerInterface: design == .a
                ? "Network framework TLS 1.2 PSK over NWListener/NWBrowser/NWConnection (Design A proof)"
                : "Network framework TLS 1.3 mutual authentication with a Secure Enclave identity (Design B proof)",
            assumptions: [
                "proof-only roster introduced by the owner; no enrollment, no Core",
                "refusal checks credited on the faulting device",
                "timing on this device's monotonic clock; wall clock for correlation only",
            ],
            requiredEvidence: ["peer identity", "TLS version and suite", "session nonce on both devices", "timings"],
            expected: "all N-1 criteria of plan §10.5 met on this cell"
                + (design == .a ? ", with an ECDHE-PSK suite" : ""),
            observed: checks.map { "\($0.id)=\($0.status.rawValue)" }.joined(separator: "; "), status: status,
            cause: cause, design: design.rawValue,
            pairSession: ProofResultRecord.PairSession(
                baseCaseID: context.caseID, role: context.role.rawValue, devices: context.devices,
                condition: context.condition, harnessNonce: context.harnessNonce, sessionCodes: codes),
            checks: checks, startedAt: startedAt)
    }

    static func record(
        caseID: String, context: ProofRunContext, configuration: [String: String], providerInterface: String,
        assumptions: [String], requiredEvidence: [String], expected: String, observed: String, status: ProofStatus,
        cause: String, design: String?, pairSession: ProofResultRecord.PairSession?, checks: [ProofResultRecord.Check],
        startedAt: (wall: String, monotonic: UInt64)
    ) -> ProofResultRecord {
        let canonical = configuration.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        return ProofResultRecord(
            runID: context.runID, caseID: caseID, commit: ProofDeviceFacts.commit,
            harnessVersion: ProofDeviceFacts.appVersion + "; harness test plan X1",
            providerInterface: providerInterface,
            configuration: ProofResultRecord.Configuration(digest: Digests.sha256Hex(canonical), fields: configuration),
            platform: ProofDeviceFacts.platform, deviceModel: ProofDeviceFacts.model,
            osVersion: ProofDeviceFacts.osVersion, xcodeVersion: ProofDeviceFacts.xcodeVersion, apnsEnvironment: nil,
            profileKind: nil, modelID: nil, assumptions: assumptions, requiredEvidence: requiredEvidence,
            expectedResult: expected, observedResult: observed, resultLevel: status == .pass ? requiredLevel : nil,
            requiredResultLevel: requiredLevel, status: status, executor: "owner", cause: cause, actions: [],
            times: ProofResultRecord.Times(
                wallClockStart: startedAt.wall, wallClockEnd: ProofEvidenceMapping.wallClock(),
                monotonicStartNanoseconds: startedAt.monotonic,
                monotonicEndNanoseconds: ProofMonotonicClock.nowNanoseconds()),
            evidenceFiles: [ProofResultStore.evidenceFile], knownFinding: nil, design: design,
            pairSession: pairSession, checks: checks)
    }
}
