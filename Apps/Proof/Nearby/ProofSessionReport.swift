// PROOF ONLY — Apps/Proof never ships. Everything one nearby session showed, as recorded evidence: TLS version and
// suite (raw values and names), the PSK identity kind, the authenticated peer, the session code shown on screen,
// any refusal, the interfaces the path used (awdl0 means peer-to-peer Wi-Fi), deduplication, and the timing reports.

struct ProofSessionReport: Codable, Sendable {
    var design: String
    var role: String
    var harnessRole: String
    var fault: String
    var suitePolicy: String?
    var tlsVersionRaw: UInt16?
    var tlsVersion: String?
    var cipherSuiteRaw: UInt16?
    var cipherSuite: String?
    var forwardSecret: Bool?
    var pskIdentityKind: String?
    var peerDeviceID: String?
    var peerLabel: String?
    var sessionCode: String?
    var authenticated = false
    var refusal: String?
    var interfaces: [String] = []
    var closedByDeduplication = false
    var rejoinSecretMatched: Bool?
    var timing: ProofTimedExchange.DriverReport?
    var echo: ProofTimedExchange.EchoReport?
    var startedAtNanoseconds: UInt64
    var authenticatedAtNanoseconds: UInt64?
    var endedAtNanoseconds: UInt64?
}
