// PROOF ONLY — Apps/Proof never ships. What the TLS layer of an established nearby connection gives the session
// layer and the result (plan §8.7, §10.5 N-1): the 32-byte exporter value under `EXPORTER-lisa-nearby-v1`
// (`sec_protocol_metadata_create_secret`, RFC 5705 / RFC 8446 §7.5, no context), and the negotiated protocol version
// and cipher suite as raw values.

import Foundation
import LisaTrust
import Network
import Security

struct ProofTLSSessionFacts: Sendable, Equatable {
    let exporter: [UInt8]
    let protocolVersionRaw: UInt16
    let cipherSuiteRaw: UInt16

    enum Failure: Error, Equatable {
        case noTLSMetadata
        case exporterUnavailable
    }

    static func read(from connection: NWConnection) throws -> ProofTLSSessionFacts {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { throw Failure.noTLSMetadata }
        let security = metadata.securityProtocolMetadata
        let label = NearbyAuthenticationTranscript.exporterLabel
        let secret = label.withCString { pointer in
            sec_protocol_metadata_create_secret(
                security, label.utf8.count, pointer, NearbyAuthenticationTranscript.exporterLength)
        }
        guard let secret else { throw Failure.exporterUnavailable }
        let exporter = [UInt8](secret as DispatchData)
        guard exporter.count == NearbyAuthenticationTranscript.exporterLength else {
            throw Failure.exporterUnavailable
        }
        return ProofTLSSessionFacts(
            exporter: exporter,
            protocolVersionRaw: sec_protocol_metadata_get_negotiated_tls_protocol_version(security).rawValue,
            cipherSuiteRaw: sec_protocol_metadata_get_negotiated_tls_ciphersuite(security).rawValue)
    }
}
