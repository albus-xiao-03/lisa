// Signing Core receipts and checking them on arrival (plan §8.2.1, R2-SYNC-03, R2-L15): Core signs the exact canonical
// body under the receipt domain. A device accepts only Core's valid signature, by the key its verified key history
// gives Core, over a well-formed receipt of its own dataset; anything else, a peer's acknowledgement included, never
// counts as Core commitment.

import LisaCrypto
import LisaSyncProtocol

/// Why a receipt was refused.
public enum ReceiptVerificationError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case wrongDataset
    case invalidSignature
}

/// Signs and verifies Core receipts.
public enum ReceiptSigning {
    public static func sign(_ receipt: CoreReceipt, with core: some MessageSigning) throws -> SignedCoreReceipt {
        let body = try receipt.canonicalBody()
        return try SignedCoreReceipt(
            body: body, signature: try DomainSignatures.sign(body, domain: .receipt, with: core))
    }

    /// Verifies an arriving receipt against Core's signing key from the verified key history, then decodes it.
    public static func verify(_ signed: SignedCoreReceipt, dataset: Identifier128, coreKey: P256Verifier)
        throws(ReceiptVerificationError) -> CoreReceipt
    {
        guard DomainSignatures.isValid(signed.signature, over: signed.body, domain: .receipt, by: coreKey) else {
            throw .invalidSignature
        }
        let receipt: CoreReceipt
        do {
            receipt = try signed.receipt()
        } catch {
            throw .malformed(error)
        }
        guard receipt.datasetID == dataset else { throw .wrongDataset }
        return receipt
    }
}
