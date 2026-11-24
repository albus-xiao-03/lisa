// PROOF ONLY — Apps/Proof never ships. Design A's PSK identities and keys (plan §8.7), all from LisaTrust's
// `NearbyPairKeys`: K_ij from the P-256 agreement keys with the dataset ID as salt; the initiator's identity is its
// own discovery tag (normal discovery) or HMAC(K_ij, "lisa-rejoin-v1" ‖ window) truncated to 16 bytes (rejoin).
//
// The listener registers every identity it may receive in advance — for each active roster peer (at most 9), its tag
// and its rejoin identity for the previous, current and next window, each with that peer's K — because Network
// framework's PSK selection hook can only pick among identities already added (docs/DECISIONS.md D-54).

import LisaCrypto
import LisaSyncProtocol
import LisaTrust

struct DesignAPSKEntry: Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case discoveryTag = "discovery-tag"
        case rejoin
    }

    let identity: [UInt8]
    let key: [UInt8]
    let peer: Identifier128
    let kind: Kind
    let window: UInt64
}

enum DesignAPSKTable {
    enum Failure: Error, Equatable {
        case noDiscoverySecret
    }

    static func pairKey(keys: ProofDeviceKeys, peer: ProofRosterEntry, dataset: Identifier128) throws -> [UInt8] {
        try NearbyPairKeys.pairKey(
            ownKey: keys.agreementKey, peerKey: peer.agreementKey, dataset: dataset, ownDevice: keys.deviceID,
            peerDevice: peer.deviceID)
    }

    static func windows(around window: UInt64) -> [UInt64] {
        [window &- 1, window, window &+ 1]
    }

    /// Everything the listener accepts in `window`: at most 9 peers × 2 kinds × 3 windows = 54 entries.
    static func listenerEntries(keys: ProofDeviceKeys, roster: ProofRoster, window: UInt64) throws
        -> [DesignAPSKEntry]
    {
        var entries: [DesignAPSKEntry] = []
        for peer in roster.activePeers {
            let key = try pairKey(keys: keys, peer: peer, dataset: roster.setup.datasetID)
            for candidate in windows(around: window) {
                if let secret = roster.setup.discoverySecret {
                    entries.append(
                        DesignAPSKEntry(
                            identity: NearbyPairKeys.discoveryTag(
                                secret: secret, window: candidate, device: peer.deviceID),
                            key: key, peer: peer.deviceID, kind: .discoveryTag, window: candidate))
                }
                entries.append(
                    DesignAPSKEntry(
                        identity: NearbyPairKeys.rejoinIdentity(pairKey: key, window: candidate), key: key,
                        peer: peer.deviceID, kind: .rejoin, window: candidate))
            }
        }
        return entries
    }

    /// The single identity and key an initiator offers to `peer`.
    static func initiatorEntry(
        keys: ProofDeviceKeys, peer: ProofRosterEntry, roster: ProofRoster, window: UInt64, rejoin: Bool
    ) throws -> DesignAPSKEntry {
        let key = try pairKey(keys: keys, peer: peer, dataset: roster.setup.datasetID)
        if rejoin {
            return DesignAPSKEntry(
                identity: NearbyPairKeys.rejoinIdentity(pairKey: key, window: window), key: key, peer: peer.deviceID,
                kind: .rejoin, window: window)
        }
        guard let secret = roster.setup.discoverySecret else { throw Failure.noDiscoverySecret }
        return DesignAPSKEntry(
            identity: NearbyPairKeys.discoveryTag(secret: secret, window: window, device: keys.deviceID), key: key,
            peer: peer.deviceID, kind: .discoveryTag, window: window)
    }
}
