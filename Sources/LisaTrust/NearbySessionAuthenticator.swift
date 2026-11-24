// Signing and checking nearby authentication transcripts (plan §8.7).

import LisaCrypto

/// Signs and checks nearby authentication transcripts.
public enum NearbySessionAuthenticator {
    /// This side's signature over the transcript.
    public static func sign(_ transcript: NearbyAuthenticationTranscript, with signer: some MessageSigning)
        throws(TrustError) -> [UInt8]
    {
        try DomainSignatures.sign(transcript.canonicalBody(), domain: .nearbyAuthentication, with: signer)
    }

    /// Whether `signature` is the peer's valid signature over the same transcript, as seen from this side. The
    /// caller supplies the peer's operation key from its newest roster; an unknown or revoked device has none.
    public static func isValid(
        _ signature: [UInt8], transcript: NearbyAuthenticationTranscript, peerOperationKey: P256Verifier
    ) -> Bool {
        guard let body = try? transcript.canonicalBody() else { return false }
        return DomainSignatures.isValid(signature, over: body, domain: .nearbyAuthentication, by: peerOperationKey)
    }
}
