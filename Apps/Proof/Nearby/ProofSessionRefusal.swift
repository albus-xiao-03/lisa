// PROOF ONLY — Apps/Proof never ships. Why the proof's session layer refused or ended a nearby session, with a
// stable code for the result (plan §8.7: there is never an unauthenticated fallback).

enum ProofSessionRefusal: Error, Equatable, Sendable {
    case tlsVersionNotAllowed(UInt16)
    case suiteNotForwardSecret(UInt16)
    case unexpectedFrame(UInt8)
    case unknownPeer
    case inactivePeer
    case rosterMismatch
    case tlsPeerMismatch
    case signatureInvalid
    case refusedByPeer
    case roleConflict

    var code: String {
        switch self {
        case .tlsVersionNotAllowed(let raw): "tls-version-not-allowed-0x\(String(raw, radix: 16))"
        case .suiteNotForwardSecret(let raw): "suite-not-forward-secret-0x\(String(raw, radix: 16))"
        case .unexpectedFrame(let kind): "unexpected-frame-\(kind)"
        case .unknownPeer: "unknown-peer"
        case .inactivePeer: "inactive-peer"
        case .rosterMismatch: "roster-epoch-or-version-mismatch"
        case .tlsPeerMismatch: "tls-identity-differs-from-hello"
        case .signatureInvalid: "transcript-signature-invalid"
        case .refusedByPeer: "refused-by-peer"
        case .roleConflict: "harness-role-conflict"
        }
    }
}
