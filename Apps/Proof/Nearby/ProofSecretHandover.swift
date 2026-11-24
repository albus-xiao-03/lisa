// PROOF ONLY — Apps/Proof never ships. Design A's discovery-secret handover inside an authenticated session (plan
// §8.7 rejoin: "the peer sends ... the current discovery secret, but only if the rejoiner is active in that roster").
// One round trip right after authentication on every Design A session: the initiator says whether it needs the
// secret; the responder answers with it (the session already proved the requester is an active roster peer) or with
// nothing.

import Foundation
import LisaCrypto

enum ProofSecretHandover {
    /// The initiator's side; returns the secret if it asked and the responder sent one.
    static func initiate(on channel: some ProofFrameChannel, needSecret: Bool) async throws -> [UInt8]? {
        try await channel.send(try ProofFrame.make(.discoverySecret, [needSecret ? 1 : 0]))
        let reply = try await channel.receive()
        guard reply.kind == .discoverySecret else { throw ProofSessionRefusal.unexpectedFrame(reply.kind.rawValue) }
        guard needSecret else { return nil }
        return reply.payload.count == 32 ? reply.payload : nil
    }

    /// The responder's side. `secret` is this device's current discovery secret, if it has one.
    static func respond(on channel: some ProofFrameChannel, secret: [UInt8]?) async throws {
        let request = try await channel.receive()
        guard request.kind == .discoverySecret, request.payload.count == 1 else {
            throw ProofSessionRefusal.unexpectedFrame(request.kind.rawValue)
        }
        let answer = request.payload == [1] ? (secret ?? []) : []
        try await channel.send(try ProofFrame.make(.discoverySecret, answer))
    }

    /// Compares secrets by digest so neither is ever printed.
    static func sameSecret(_ lhs: [UInt8]?, _ rhs: [UInt8]?) -> Bool {
        guard let lhs, let rhs else { return false }
        return Digests.constantTimeEquals(Digests.sha256(Data(lhs)), Digests.sha256(Data(rhs)))
    }
}
