// PROOF ONLY — Apps/Proof never ships. Design A's Bonjour discovery (plan §8.7): the listener publishes a random
// instance name and, in its TXT record, only its rotating tag for the current window; the initiator recognizes a
// roster peer by recomputing tags for the previous, current and next window. Nothing else identifying is published.

import LisaSyncProtocol
import LisaTrust
import Network

enum DesignADiscovery {
    static let serviceType = "_lisaproof-a._tcp"
    static let tagKey = "t"

    static func txtRecord(tag: [UInt8]) -> NWTXTRecord {
        NWTXTRecord([tagKey: StrictBase64URL.encode(tag)])
    }

    /// The active roster peer that published this browse result's tag, if any; never this device.
    static func peer(for result: NWBrowser.Result, roster: ProofRoster, window: UInt64) -> ProofRosterEntry? {
        guard let secret = roster.setup.discoverySecret, case .bonjour(let txt) = result.metadata,
            let text = txt[tagKey], let tag = try? StrictBase64URL.decode(text)
        else { return nil }
        return roster.activePeers.first { peer in
            DesignAPSKTable.windows(around: window).contains {
                NearbyPairKeys.discoveryTag(secret: secret, window: $0, device: peer.deviceID) == tag
            }
        }
    }
}
