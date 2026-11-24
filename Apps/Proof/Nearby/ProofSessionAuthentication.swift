// PROOF ONLY — Apps/Proof never ships. The session layer of plan §8.7 under either design, after TLS: a hello each
// way, then each side signs the exporter-bound transcript (LisaTrust's `NearbyAuthenticationTranscript`, domain
// `lisa-nearby-auth-v1`) with its operation key and checks the peer's signature against the proof roster. A relay
// sees two exporter values, so its sessions fail here before any data moves. Each side then sends its verdict.

import Foundation
import LisaCrypto
import LisaSyncProtocol
import LisaTrust

struct ProofSessionAuthentication: Sendable {
    struct Outcome: Sendable {
        let peer: ProofRosterEntry
        let ownHello: NearbyHello
        let peerHello: NearbyHello
        /// Shown on both screens and recorded on both devices: equal only when both share this TLS session.
        let sessionCode: String
    }

    let roster: ProofRoster
    let keys: ProofDeviceKeys
    let fault: ProofFaultInjection

    /// - Parameter tlsPeer: Design B's roster entry matched from the peer's leaf key; nil for Design A, whose PSK
    ///   already limits the handshake to active roster peers.
    func run(
        on channel: some ProofFrameChannel, role: NearbyRole, tls: ProofTLSSessionFacts, tlsPeer: Identifier128?
    ) async throws -> Outcome {
        let ownHello = try NearbyHello(
            deviceID: keys.deviceID, rosterEpoch: roster.epoch, rosterVersion: roster.version, head: roster.head,
            nonce: Array(RandomTokens.bytes(NearbyHello.nonceLength)))
        try await channel.send(try ProofFrame.make(.hello, try ownHello.canonicalBody()))
        let helloFrame = try await channel.receive()
        guard helloFrame.kind == .hello else { throw ProofSessionRefusal.unexpectedFrame(helloFrame.kind.rawValue) }
        let peerHello = try NearbyHello(canonicalBody: helloFrame.payload)

        guard let peer = roster.entry(for: peerHello.deviceID), peer.deviceID != keys.deviceID else {
            throw ProofSessionRefusal.unknownPeer
        }
        guard peer.active else { throw ProofSessionRefusal.inactivePeer }
        guard peerHello.rosterEpoch == roster.epoch, peerHello.rosterVersion == roster.version else {
            throw ProofSessionRefusal.rosterMismatch
        }
        if let tlsPeer, tlsPeer != peerHello.deviceID { throw ProofSessionRefusal.tlsPeerMismatch }

        let (initiator, responder) = role == .initiator ? (ownHello, peerHello) : (peerHello, ownHello)
        var signedExporter = tls.exporter
        if fault == .wrongExporterBinding { signedExporter[0] ^= 0x01 }
        let ownTranscript = try NearbyAuthenticationTranscript(
            exporter: signedExporter, initiator: initiator, responder: responder, signer: role)
        let signature = try NearbySessionAuthenticator.sign(ownTranscript, with: keys.operationSigner)
        try await channel.send(try ProofFrame.make(.authentication, signature))

        let authFrame = try await channel.receive()
        guard authFrame.kind == .authentication else {
            throw ProofSessionRefusal.unexpectedFrame(authFrame.kind.rawValue)
        }
        let peerTranscript = try NearbyAuthenticationTranscript(
            exporter: tls.exporter, initiator: initiator, responder: responder,
            signer: role == .initiator ? .responder : .initiator)
        let valid = NearbySessionAuthenticator.isValid(
            authFrame.payload, transcript: peerTranscript, peerOperationKey: peer.operationKey)
        try await channel.send(try ProofFrame.make(.verdict, [valid ? 1 : 0]))
        guard valid else {
            channel.close()
            throw ProofSessionRefusal.signatureInvalid
        }
        let verdict = try await channel.receive()
        guard verdict.kind == .verdict, verdict.payload == [1] else { throw ProofSessionRefusal.refusedByPeer }
        return Outcome(
            peer: peer, ownHello: ownHello, peerHello: peerHello,
            sessionCode: Self.sessionCode(exporter: tls.exporter, initiator: initiator, responder: responder))
    }

    /// The first 5 bytes of SHA-256("lisa-proof-session-v1" ‖ exporter ‖ initiator nonce ‖ responder nonce), as
    /// 10 hexadecimal digits in two groups.
    static func sessionCode(exporter: [UInt8], initiator: NearbyHello, responder: NearbyHello) -> String {
        let input = Array("lisa-proof-session-v1".utf8) + exporter + initiator.nonce + responder.nonce
        let digits = LowercaseHexText.encode(Array(Digests.sha256(Data(input)).prefix(5)))
        return String(digits.prefix(5)) + "-" + String(digits.suffix(5))
    }
}
