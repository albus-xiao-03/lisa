// PROOF ONLY — Apps/Proof never ships. Design B's roster pinning (plan §8.7): the peer's leaf certificate key,
// reduced to the SHA-256 of its canonical P-256 SPKI and matched against the active roster entries. No CA chain, no
// host name and no system trust evaluation are involved.

import Foundation
import LisaCrypto
import LisaSyncProtocol
import Network
import Security

enum ProofPeerKeyPin {
    /// SHA-256 of the canonical SPKI of the certificate's key; nil unless it is an uncompressed P-256 key.
    static func spkiSHA256(of certificate: SecCertificate) -> Digest256? {
        guard let key = SecCertificateCopyKey(certificate),
            let point = SecKeyCopyExternalRepresentation(key, nil) as Data?, point.count == 65, point.first == 0x04,
            let verifier = try? P256Verifier(canonicalSPKI: ProofCertificateEncoder.p256SPKIPrefix + Array(point))
        else { return nil }
        return try? Digest256(bytes: verifier.fingerprint)
    }

    /// The leaf certificate a verify block receives.
    static func leaf(of trust: sec_trust_t) -> SecCertificate? {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        return (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first
    }

    /// The peer's leaf on an established connection, for binding the TLS identity to the hello's device ID.
    static func leaf(of connection: NWConnection) -> SecCertificate? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { return nil }
        var leaf: SecCertificate?
        _ = sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            if leaf == nil { leaf = sec_certificate_copy_ref(certificate).takeRetainedValue() }
        }
        return leaf
    }

    /// The active roster peer whose pin matches `certificate`.
    static func peer(for certificate: SecCertificate?, roster: ProofRoster) -> ProofRosterEntry? {
        guard let certificate, let pin = spkiSHA256(of: certificate) else { return nil }
        return roster.activePeer(forTLSKey: pin)
    }
}
