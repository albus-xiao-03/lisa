// PROOF ONLY — Apps/Proof never ships. The pipeline of one established nearby connection under either design
// (plan §8.7): check the negotiated TLS version and suite, bind Design B's TLS peer to the roster, run the session
// layer, hand over Design A's discovery secret, apply deduplication, then the timed exchange of the harness role.

import Foundation
import LisaSyncProtocol
import LisaTrust
import Network

struct ProofSessionRunner: Sendable {
    let configuration: ProofNearbyConfiguration
    let roster: ProofRoster
    /// This side's identity for this connection: the enrolled keys or an injected fault's throwaway keys.
    let keys: ProofDeviceKeys
    /// The discovery secret this side hands over as a responder (nil while acting as a rejoining device).
    let handoverSecret: [UInt8]?
    /// The secret a rejoining initiator expects to receive, compared by digest only.
    let expectedSecret: [UInt8]?

    func run(
        connection: NWConnection, role: NearbyRole, pskKind: DesignAPSKEntry.Kind?,
        admit: @escaping @Sendable (ProofSessionAuthentication.Outcome) async -> Bool,
        stillLive: @escaping @Sendable () async -> Bool
    ) async -> ProofSessionReport {
        var report = ProofSessionReport(
            design: configuration.design.rawValue, role: role.rawValue,
            harnessRole: configuration.harnessRole.rawValue, fault: configuration.fault.rawValue,
            startedAtNanoseconds: ProofMonotonicClock.nowNanoseconds())
        report.pskIdentityKind = pskKind?.rawValue
        if configuration.design == .a { report.suitePolicy = configuration.suitePolicy.rawValue }
        report.interfaces = connection.currentPath?.availableInterfaces.map(\.name) ?? []
        let channel = NWConnectionFrameChannel(connection: connection)
        do {
            let tls = try ProofTLSSessionFacts.read(from: connection)
            report.tlsVersionRaw = tls.protocolVersionRaw
            report.tlsVersion = ProofCipherSuiteNames.version(tls.protocolVersionRaw)
            report.cipherSuiteRaw = tls.cipherSuiteRaw
            report.cipherSuite = ProofCipherSuiteNames.suite(tls.cipherSuiteRaw)
            var tlsPeer: Identifier128?
            switch configuration.design {
            case .a:
                guard tls.protocolVersionRaw == 0x0303 else {
                    throw ProofSessionRefusal.tlsVersionNotAllowed(tls.protocolVersionRaw)
                }
                let forwardSecret = DesignAPSKSuites.isForwardSecret(tls.cipherSuiteRaw)
                report.forwardSecret = forwardSecret
                if configuration.suitePolicy == .forwardSecretOnly, !forwardSecret {
                    throw ProofSessionRefusal.suiteNotForwardSecret(tls.cipherSuiteRaw)
                }
            case .b:
                guard tls.protocolVersionRaw == 0x0304 else {
                    throw ProofSessionRefusal.tlsVersionNotAllowed(tls.protocolVersionRaw)
                }
                guard let peer = ProofPeerKeyPin.peer(for: ProofPeerKeyPin.leaf(of: connection), roster: roster) else {
                    throw ProofSessionRefusal.unknownPeer
                }
                tlsPeer = peer.deviceID
            }
            let outcome = try await ProofSessionAuthentication(
                roster: roster, keys: keys, fault: configuration.fault
            ).run(on: channel, role: role, tls: tls, tlsPeer: tlsPeer)
            report.authenticated = true
            report.authenticatedAtNanoseconds = ProofMonotonicClock.nowNanoseconds()
            report.peerDeviceID = outcome.peer.deviceID.hex
            report.peerLabel = outcome.peer.card.label
            report.sessionCode = outcome.sessionCode
            if configuration.design == .a {
                if role == .initiator {
                    let received = try await ProofSecretHandover.initiate(on: channel, needSecret: configuration.rejoin)
                    if configuration.rejoin {
                        report.rejoinSecretMatched = ProofSecretHandover.sameSecret(received, expectedSecret)
                    }
                } else {
                    try await ProofSecretHandover.respond(on: channel, secret: handoverSecret)
                }
            }
            guard await admit(outcome) else {
                report.closedByDeduplication = true
                channel.close()
                report.endedAtNanoseconds = ProofMonotonicClock.nowNanoseconds()
                return report
            }
            // Both devices admit their sessions independently; a short settle lets the loser close first.
            try await Task.sleep(for: .milliseconds(1_500))
            guard await stillLive() else {
                report.closedByDeduplication = true
                channel.close()
                report.endedAtNanoseconds = ProofMonotonicClock.nowNanoseconds()
                return report
            }
            switch configuration.harnessRole {
            case .sender:
                report.timing = try await ProofTimedExchange().drive(
                    on: channel, payloadBytes: configuration.framePayloadBytes,
                    sendOversizeHeader: configuration.fault == .oversizeFrameHeader)
            case .receiver:
                report.echo = await ProofTimedExchange().echo(on: channel)
            }
            channel.close()
        } catch let refusal as ProofSessionRefusal {
            report.refusal = refusal.code
            channel.close()
        } catch {
            report.refusal = "error: \(error)"
            channel.close()
        }
        report.endedAtNanoseconds = ProofMonotonicClock.nowNanoseconds()
        return report
    }
}
