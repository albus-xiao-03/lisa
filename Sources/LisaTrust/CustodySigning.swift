// Signing custody acknowledgements and checking them on arrival (plan §8.6.1, §8.7): the holder signs the exact
// canonical body under the custody domain with its operation key. A replica accepts only the holder's valid signature,
// by the key its newest verified roster gives that device, over a well-formed acknowledgement of its own dataset.

import LisaCrypto
import LisaSyncProtocol

/// Why a custody acknowledgement was refused.
public enum CustodyVerificationError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case wrongDataset
    /// The roster gives the holder no key.
    case unknownHolder
    case invalidSignature
}

/// Signs and verifies custody acknowledgements.
public enum CustodySigning {
    public static func sign(_ acknowledgement: CustodyAcknowledgement, with holder: some MessageSigning) throws
        -> SignedCustodyAcknowledgement
    {
        let body = try acknowledgement.canonicalBody()
        return try SignedCustodyAcknowledgement(
            body: body, signature: try DomainSignatures.sign(body, domain: .custodyAcknowledgement, with: holder))
    }

    /// Decodes and verifies an arriving acknowledgement against the holder's key from the newest verified roster.
    public static func verify(
        _ signed: SignedCustodyAcknowledgement, dataset: Identifier128, holderKey: (Identifier128) -> P256Verifier?
    ) throws(CustodyVerificationError) -> CustodyAcknowledgement {
        let acknowledgement: CustodyAcknowledgement
        do {
            acknowledgement = try signed.acknowledgement()
        } catch {
            throw .malformed(error)
        }
        guard acknowledgement.datasetID == dataset else { throw .wrongDataset }
        guard let key = holderKey(acknowledgement.holderDeviceID) else { throw .unknownHolder }
        guard
            DomainSignatures.isValid(signed.signature, over: signed.body, domain: .custodyAcknowledgement, by: key)
        else { throw .invalidSignature }
        return acknowledgement
    }
}
