// PROOF ONLY — Apps/Proof never ships. NWParameters for Design A (plan §8.7): TCP with keepalives, TLS exactly 1.2
// (TN3213: TLS-PSK is 1.2-only and works only with this older Network framework API), the PSK entries added with
// `sec_protocol_options_add_pre_shared_key`, only the offered suites by raw value, and peer-to-peer Wi-Fi included.
// An optional probe installs a PSK selection block on the listener to record whether Network framework ever calls it
// there (the plan's §8.7 text assumes a listener-side selection; docs/DECISIONS.md D-54).

import Foundation
import Network
import Security

enum DesignAParameters {
    static func make(
        entries: [DesignAPSKEntry], policy: DesignAPSKSuites.Policy,
        selectionProbe: (@Sendable (_ hintBytes: Int?) -> Void)? = nil
    ) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        for entry in entries {
            sec_protocol_options_add_pre_shared_key(options, dispatchData(entry.key), dispatchData(entry.identity))
        }
        for raw in DesignAPSKSuites.offered(policy) {
            if let suite = tls_ciphersuite_t(rawValue: raw) {
                sec_protocol_options_append_tls_ciphersuite(options, suite)
            }
        }
        if let selectionProbe {
            sec_protocol_options_set_pre_shared_key_selection_block(
                options,
                { _, hint, complete in
                    selectionProbe(hint.map { ($0 as DispatchData).count })
                    complete(hint)
                }, DispatchQueue(label: "org.example.lisa.proof.psk-selection"))
        }
        let parameters = NWParameters(tls: tls, tcp: ProofTCPOptions.make())
        parameters.includePeerToPeer = true
        return parameters
    }

    static func dispatchData(_ bytes: [UInt8]) -> __DispatchData {
        bytes.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    }
}
