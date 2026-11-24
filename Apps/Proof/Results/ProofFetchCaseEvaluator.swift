// PROOF ONLY — Apps/Proof never ships. Judges one E-1 probe subcase against its expectation (plan §8.9.3) and
// builds the case's `results.jsonl` record from its subcases and the owner's observation (the listener or proxy log,
// which only the owner can see). Extra conditions: NAT64 cases need an IPv6-only path with a discovered prefix,
// dual-stack cases a dual-stack path, and the translated-destination case no IPv6 dial at all.

import Foundation

@MainActor
enum ProofFetchCaseEvaluator {
    static func evaluate(_ trace: ProbeFetchTrace, subcase: ProbeSubcase, caseID: String) -> (ProofStatus, String) {
        var problems: [String] = []
        if !subcase.passingOutcomes.contains(trace.finalOutcome) {
            problems.append(
                "outcome \(trace.finalOutcome), expected \(subcase.passingOutcomes.sorted().joined(separator: " or "))")
        }
        if caseID.hasSuffix("FETCH-05"), trace.pathKind != .ipv6Only || (trace.nat64?.prefixes.isEmpty ?? true) {
            problems.append("path \(trace.pathKind.rawValue), prefixes \(trace.nat64?.prefixes.map(\.text) ?? [])")
        }
        if caseID.hasSuffix("FETCH-06"), trace.pathKind != .dualStack {
            problems.append("path \(trace.pathKind.rawValue), expected dual-stack")
        }
        let dialedIPv6 = trace.hops.flatMap(\.dials).contains { $0.target.contains(":") }
        if caseID.hasSuffix("FETCH-07"), dialedIPv6 { problems.append("an IPv6 address was dialed") }
        let summary =
            "\(trace.finalOutcome) on \(trace.interface) (\(trace.pathKind.rawValue)); dials: "
            + trace.hops.flatMap(\.dials).map { "\($0.target) \($0.outcome)" }.joined(separator: ", ")
        return problems.isEmpty ? (.pass, summary) : (.fail, summary + "; " + problems.joined(separator: "; "))
    }

    static func record(
        for probeCase: ProbeCase, evidence: [ProofEvidenceEntry], ownerObservation: ProofStatus?,
        context: ProofRunContext,
        startedAt: (wall: String, monotonic: UInt64)
    ) -> ProofResultRecord {
        let mine = evidence.filter { $0.caseID == probeCase.id }
        var checks = probeCase.subcases.map { subcase in
            let matching = mine.filter { $0.check == subcase.id }
            return ProofResultRecord.Check(
                id: subcase.id, status: matching.last?.status ?? .notRunEnvironment,
                observed: matching.last?.observed ?? "not yet run", evidenceEntries: matching.count)
        }
        if let observation = probeCase.ownerObservation {
            checks.append(
                ProofResultRecord.Check(
                    id: "owner-observation", status: ownerObservation ?? .notRunEnvironment, observed: observation,
                    evidenceEntries: ownerObservation == nil ? 0 : 1))
        }
        let failed = checks.filter { $0.status == .fail }.map(\.id)
        let missing = checks.filter { $0.status != .pass && $0.status != .fail }.map(\.id)
        let status: ProofStatus = !failed.isEmpty ? .fail : (missing.isEmpty ? .pass : .notRunEnvironment)
        return ProofCellAggregator.record(
            caseID: probeCase.id, context: context, configuration: ["case": probeCase.id, "coreConfigured": "false"],
            providerInterface:
                "dns_sd (DNSServiceGetAddrInfo, DNSServiceQueryRecord) + Network framework NWConnection, Core unavailable",
            assumptions: [
                "no Core configured", "URLs and names are the owner's controlled endpoints", probeCase.setup,
            ],
            requiredEvidence: [
                "per-hop decision", "scoped resolution with TTLs", "every dial", "owner's listener observation",
            ],
            expected: probeCase.title,
            observed: checks.map { "\($0.id)=\($0.status.rawValue)" }.joined(separator: "; "),
            status: status,
            cause: status == .pass
                ? "all subcases met plan §8.9.3"
                : (failed.isEmpty
                    ? "pending owner session: \(missing.joined(separator: ", "))"
                    : "failed: \(failed.joined(separator: ", "))"),
            design: nil, pairSession: nil, checks: checks, startedAt: startedAt)
    }
}
