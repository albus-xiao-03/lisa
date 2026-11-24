// Writing a protected archive (plan §8.6.6): a random key encrypts the payload, HPKE seals the key to each
// recipient, and the exporting device signs the result or marks it unsigned.

import LisaCrypto
import LisaSyncProtocol
import LisaTrust

/// Seals archives.
public enum ArchiveWriter {
    /// What the archive is about.
    public struct Context: Sendable {
        public let datasetID: Identifier128
        public let originDeviceID: Identifier128
        public let incarnations: [Identifier128]
        public let createdAt: Int64
        public let rosterVersion: Int64
        public let head: Digest256

        public init(
            datasetID: Identifier128, originDeviceID: Identifier128, incarnations: [Identifier128], createdAt: Int64,
            rosterVersion: Int64, head: Digest256
        ) {
            self.datasetID = datasetID
            self.originDeviceID = originDeviceID
            self.incarnations = incarnations
            self.createdAt = createdAt
            self.rosterVersion = rosterVersion
            self.head = head
        }
    }

    /// Seals `entries` to `recipients`, signed by `signer` when one is available.
    public static func seal(
        _ entries: [ArchiveEntry], context: Context,
        recipients: [(kind: ArchiveRecipientKind, key: P256AgreementPublicKey)], signer: (any MessageSigning)?
    ) throws(ArchiveError) -> ArchiveContainer {
        let archiveID = Identifier128.random()
        let payloadKey = AESGCM256.randomKey()
        let nonce = AESGCM256.randomNonce()
        var sealedRecipients: [ArchiveRecipient] = []
        for (kind, key) in recipients {
            let keyID = ArchiveRecipient.keyID(of: key)
            guard
                let sealed = try? HPKEP256.seal(
                    payloadKey, to: key, info: ArchiveRecipient.info(archiveID: archiveID),
                    authenticatedData: ArchiveRecipient.authenticatedData(kind: kind, keyID: keyID))
            else { throw .sealFailed }
            sealedRecipients.append(
                ArchiveRecipient(
                    kind: kind, keyID: keyID, encapsulatedKey: sealed.encapsulatedKey, sealedKey: sealed.ciphertext))
        }
        sealedRecipients.sort { $0.keyID.bytes.lexicographicallyPrecedes($1.keyID.bytes) }
        let plaintext = ArchivePayload.encode(entries)
        let header = try ArchiveHeader(
            archiveID: archiveID, datasetID: context.datasetID, originDeviceID: context.originDeviceID,
            incarnations: context.incarnations.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) },
            createdAt: context.createdAt, rosterVersion: context.rosterVersion, head: context.head,
            recipients: sealedRecipients, signerKeyID: signer.map { ArchiveDigest.keyID(ofSPKI: $0.verifier.spkiDER) },
            payloadNonce: nonce, payloadLength: Int64(plaintext.count + AESGCM256.tagLength))
        let headerBody = try header.canonicalBody()
        guard
            let ciphertext = try? AESGCM256.seal(
                plaintext, key: payloadKey, nonce: nonce, authenticatedData: ArchiveDigest.sha256(headerBody))
        else { throw .sealFailed }
        var container = ArchiveContainer(headerBody: headerBody, header: header, ciphertext: ciphertext, signature: nil)
        if let signer {
            guard let signature = try? DomainSignatures.sign(container.signedDigests, domain: .archive, with: signer)
            else { throw .sealFailed }
            container = ArchiveContainer(
                headerBody: headerBody, header: header, ciphertext: ciphertext, signature: signature)
        }
        return container
    }
}
