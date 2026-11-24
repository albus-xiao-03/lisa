// PROOF ONLY — Apps/Proof never ships. What one probe fetch observed, hop by hop, as recorded evidence: the
// interface and path, each hop's check 1 result, decision, scoped resolution with TTLs, NAT64 evidence, every dial
// (so "never dialed by its AAAA" and "no connection to a refused address" are visible), the response and the
// outcome. URLs appear as their origin and a SHA-256 digest only (R1's logging rule, `URLPolicy.origin`).

struct ProbeHop: Codable, Sendable {
    var origin: String
    var urlSHA256: String
    var check1: String = "ok"
    var decision: String = ""
    var resolution: ProbeResolution?
    var minimumTTL: UInt32?
    var dials: [ProbeDialRecord] = []
    var response: ProbeHTTPResponse?
    /// fetched, redirect, refused-before-connect, deferred-to-core, failed-closed, failed-after-connect.
    var outcome: String = ""
    var message: String?
}

struct ProbeFetchTrace: Codable, Sendable {
    var interface: String
    var interfaceIndex: UInt32
    var pathKind: ProbePathKind
    var availableInterfaces: [String]
    var nat64: ProbeNAT64Evidence?
    var hops: [ProbeHop] = []
    /// The summary compared with a case's expectation: fetched, refused-before-connect, deferred-to-core,
    /// redirect-stopped-refused, redirect-stopped-deferred, failed-closed, redirect-limit.
    var finalOutcome: String = ""
    var evidenceExpired = false
}
