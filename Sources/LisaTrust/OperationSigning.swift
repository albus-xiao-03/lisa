// Signing operations and checking them on arrival (plan §8.2.1; R2-L16: forged signatures and wrong datasets).

import LisaCrypto
import LisaSyncProtocol

/// Why a signed operation was refused before its payload was looked at.
public enum OperationVerificationError: Error, Hashable, Sendable {
    /// The body is malformed (`rejected: malformed`).
    case malformed(OperationEnvelopeError)
    /// The operation names another dataset.
    case wrongDataset
    /// The signature is not the origin's valid signature over `"lisa-r2-op\n" ‖ body`.
    case invalidSignature
    /// A device-signed operation claiming Core's legacy origin, or a legacy child not signed by Core.
    case originKeyMismatch
}

/// Signs envelopes and verifies signed operations.
public enum OperationSigning {
    /// Encodes `envelope` canonically and signs the exact body under the operation domain.
    public static func sign(_ envelope: OperationEnvelope, with signer: some MessageSigning) throws -> SignedOperation {
        let body = try envelope.canonicalBody()
        let signature = try DomainSignatures.sign(body, domain: .operation, with: signer)
        return try SignedOperation(body: body, signature: signature)
    }

    /// Decodes and verifies an arriving operation.
    /// - Parameters:
    ///   - dataset: the receiving dataset; any other is refused.
    ///   - deviceKey: resolves a device's operation key from the holder's roster (`nil` for an unknown or revoked
    ///     device, which refuses the operation).
    ///   - coreKey: Core's signing key valid for legacy children (from the verified key history).
    public static func verify(
        _ operation: SignedOperation, dataset: Identifier128, deviceKey: (Identifier128) -> P256Verifier?,
        coreKey: P256Verifier?
    ) throws(OperationVerificationError) -> OperationEnvelope {
        let envelope: OperationEnvelope
        do {
            envelope = try operation.envelope()
        } catch {
            throw .malformed(error)
        }
        guard envelope.datasetID == dataset else { throw .wrongDataset }
        let key: P256Verifier?
        switch envelope.origin {
        case .device(let device, _, _, _):
            key = deviceKey(device)
        case .coreLegacyTranslation:
            key = coreKey
        }
        guard let key else { throw .originKeyMismatch }
        guard DomainSignatures.isValid(operation.signature, over: operation.body, domain: .operation, by: key) else {
            throw .invalidSignature
        }
        return envelope
    }
}
