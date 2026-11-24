// PROOF ONLY — Apps/Proof never ships. NWParameters for Design B (plan §8.7): TLS exactly 1.3, this device's
// Secure-Enclave-backed proof identity as the local identity, peer authentication required (mutual TLS), and a verify
// block that accepts a peer only if its leaf key matches an active proof-roster pin. Peer-to-peer Wi-Fi included.

import Foundation
import Network
import Security

enum DesignBParameters {
    static let serviceType = "_lisaproof-b._tcp"

    /// - Parameter observe: called from the verify block with the matched peer's device ID hex, or nil on refusal.
    static func make(
        identity: sec_identity_t, roster: ProofRoster, observe: (@Sendable (_ matchedDeviceHex: String?) -> Void)? = nil
    ) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, identity)
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_verify_block(
            options,
            { _, trust, complete in
                let peer = ProofPeerKeyPin.peer(for: ProofPeerKeyPin.leaf(of: trust), roster: roster)
                observe?(peer?.deviceID.hex)
                complete(peer != nil)
            }, DispatchQueue(label: "org.example.lisa.proof.verify"))
        let parameters = NWParameters(tls: tls, tcp: ProofTCPOptions.make())
        parameters.includePeerToPeer = true
        return parameters
    }
}
