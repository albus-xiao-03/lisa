// Opening a protected archive (plan §8.6.6): decryption with a recipient key, and authenticity checked apart from
// decryption against the exporting device's key in the trusted roster.

import LisaCrypto
import LisaSyncProtocol
import LisaTrust

/// Opens archives and checks their signatures.
public enum ArchiveReader {
    /// The entries, decrypted with `key` for the expected dataset. Opening only decrypts: it says nothing about who
    /// made the archive, which `isAuthentic` checks separately, and nothing about eligibility, which the importer
    /// decides entry by entry against trusted revocation evidence (§8.6.6, M5).
    public static func open(_ container: ArchiveContainer, with key: P256AgreementKey, dataset: Identifier128)
        throws(ArchiveError) -> [ArchiveEntry]
    {
        guard container.header.datasetID == dataset else { throw .wrongDataset }
        let keyID = ArchiveRecipient.keyID(of: key.publicKey)
        guard let recipient = container.header.recipients.first(where: { $0.keyID == keyID }) else {
            throw .notARecipient
        }
        guard
            let payloadKey = try? HPKEP256.open(
                HPKESealedMessage(encapsulatedKey: recipient.encapsulatedKey, ciphertext: recipient.sealedKey),
                with: key, info: ArchiveRecipient.info(archiveID: container.header.archiveID),
                authenticatedData: ArchiveRecipient.authenticatedData(kind: recipient.kind, keyID: keyID)),
            let plaintext = try? AESGCM256.open(
                container.ciphertext, key: payloadKey, nonce: container.header.payloadNonce,
                authenticatedData: ArchiveDigest.sha256(container.headerBody))
        else { throw .decryptionFailed }
        return try ArchivePayload.decode(plaintext)
    }

    /// Whether the archive carries a valid signature by `signer`, the exporting device's key from the trusted
    /// roster. An unsigned archive is never authentic.
    public static func isAuthentic(_ container: ArchiveContainer, signer: P256Verifier) -> Bool {
        guard let signature = container.signature, let named = container.header.signerKeyID,
            named == ArchiveDigest.keyID(ofSPKI: signer.spkiDER)
        else { return false }
        return DomainSignatures.isValid(signature, over: container.signedDigests, domain: .archive, by: signer)
    }
}
