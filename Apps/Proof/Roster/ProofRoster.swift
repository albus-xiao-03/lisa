// PROOF ONLY — Apps/Proof never ships. The proof roster: this device's card, the peers' cards the owner entered,
// and which of them are active. It answers the session layer's questions (who is this device ID, is it active,
// whose TLS key is this) and supplies the hello's roster epoch, version and head (plan §8.7). At most 10 devices,
// so at most 9 peers, as the plan's discovery and rejoin bounds assume.

import Foundation
import LisaCrypto
import LisaSyncProtocol

struct ProofRosterEntry: Sendable, Hashable {
    let card: ProofDeviceCard
    var active: Bool

    var deviceID: Identifier128 { card.deviceID }
    var operationKey: P256Verifier { card.operationKey }
    var agreementKey: P256AgreementPublicKey { card.agreementKey }
}

struct ProofRoster: Sendable {
    static let maximumDevices = 10

    let setup: ProofSetupText
    let ownDeviceID: Identifier128
    let entries: [ProofRosterEntry]

    enum Failure: Error, Equatable {
        case tooManyDevices, duplicateDevice, ownCardMissing
    }

    init(setup: ProofSetupText, ownDeviceID: Identifier128, entries: [ProofRosterEntry]) throws {
        guard entries.count <= Self.maximumDevices else { throw Failure.tooManyDevices }
        guard Set(entries.map(\.deviceID)).count == entries.count else { throw Failure.duplicateDevice }
        guard entries.contains(where: { $0.deviceID == ownDeviceID }) else { throw Failure.ownCardMissing }
        self.setup = setup
        self.ownDeviceID = ownDeviceID
        self.entries = entries
    }

    var epoch: Identifier128 { setup.rosterEpoch }
    var version: Int64 { setup.rosterVersion }

    /// A synthetic head: SHA-256 over a domain string, then each entry's device ID and active flag in device-ID
    /// order. Devices with the same cards and flags agree on it; it stands in for the sync head of plan §8.7.
    var head: Digest256 {
        var input = Array("lisa-proof-head-v1\n".utf8)
        for entry in entries.sorted(by: { $0.deviceID.bytes.lexicographicallyPrecedes($1.deviceID.bytes) }) {
            input += entry.deviceID.bytes + [entry.active ? 1 : 0]
        }
        // swift-format-ignore: the digest is always 32 bytes.
        return try! Digest256(bytes: Array(Digests.sha256(Data(input))))
    }

    func entry(for deviceID: Identifier128) -> ProofRosterEntry? {
        entries.first { $0.deviceID == deviceID }
    }

    /// The active peers, never this device; at most 9.
    var activePeers: [ProofRosterEntry] {
        entries.filter { $0.active && $0.deviceID != ownDeviceID }
    }

    /// The active peer whose Design B TLS key has this SPKI hash.
    func activePeer(forTLSKey hash: Digest256) -> ProofRosterEntry? {
        activePeers.first { $0.card.tlsKeySHA256 == hash }
    }
}
