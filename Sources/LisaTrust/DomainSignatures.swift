// Signing and verifying bodies under a signing domain (plan §8.16.1).

import LisaCrypto

/// Signs and verifies bodies under a signing domain.
public enum DomainSignatures {
    /// The raw signature over `domain.prefix ‖ body`.
    public static func sign(_ body: [UInt8], domain: SigningDomain, with signer: some MessageSigning)
        throws(TrustError) -> [UInt8]
    {
        do {
            let signature = try signer.rawSignature(for: domain.message(for: body))
            guard signature.count == 64 else { throw TrustError.signingFailed }
            return signature
        } catch {
            throw .signingFailed
        }
    }

    /// Whether `signature` is `verifier`'s raw signature over `domain.prefix ‖ body`.
    public static func isValid(
        _ signature: [UInt8], over body: [UInt8], domain: SigningDomain, by verifier: P256Verifier
    ) -> Bool {
        verifier.isValidSignature(signature, for: domain.message(for: body))
    }
}
