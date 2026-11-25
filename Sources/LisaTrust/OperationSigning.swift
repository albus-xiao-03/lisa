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
    ///   - previousKeys: for operations Core committed (in its signed pages and snapshots), the device's other keys
    ///     from the roster: those it rotated away from, and its key if it was revoked since (§8.1.3, §8.1.4). Empty
    ///     for anything else, so only the current key verifies new work.
    ///   - coreKey: Core's signing key valid for legacy children (from the verified key history).
    public static func verify(
        _ operation: SignedOperation, dataset: Identifier128, deviceKey: (Identifier128) -> P256Verifier?,
        previousKeys: (Identifier128) -> [P256Verifier] = { _ in [] }, coreKey: P256Verifier?
    ) throws(OperationVerificationError) -> OperationEnvelope {
        let envelope: OperationEnvelope
        do {
            envelope = try operation.envelope()
        } catch {
            throw .malformed(error)
        }
        guard envelope.datasetID == dataset else { throw .wrongDataset }
        let keys: [P256Verifier]
        switch envelope.origin {
        case .device(let device, _, _, _):
            keys = (deviceKey(device).map { [$0] } ?? []) + previousKeys(device)
        case .coreLegacyTranslation:
            keys = coreKey.map { [$0] } ?? []
        }
        guard !keys.isEmpty else { throw .originKeyMismatch }
        guard
            keys.contains(where: {
                DomainSignatures.isValid(operation.signature, over: operation.body, domain: .operation, by: $0)
            })
        else { throw .invalidSignature }
        return envelope
    }
}
