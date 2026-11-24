// PROOF ONLY — Apps/Proof never ships. TCP options both designs share (plan §8.7 connection behavior): keepalives
// so a vanished peer is noticed, no Nagle delay for the small session frames, and a bounded connection timeout.

import Network

enum ProofTCPOptions {
    static func make() -> NWProtocolTCP.Options {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        tcp.connectionTimeout = 15
        return tcp
    }
}
