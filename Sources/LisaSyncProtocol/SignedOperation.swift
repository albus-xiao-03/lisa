// The wire unit of an operation: its exact signed body and the raw signature beside it (plan §8.2.1, §8.16.1).

/// A signed operation as it travels: the canonical body bytes and the 64-byte signature over
/// `"lisa-r2-op\n" ‖ body`. Relays forward exactly these bytes. The signature is not part of the digest.
public struct SignedOperation: Hashable, Sendable {
    public let body: [UInt8]
    public let signature: [UInt8]

    /// - Throws: `OperationEnvelopeError.invalidField("signature")` unless the signature is 64 bytes, and
    ///   `.encoding` unless the body is within the 64 KiB limit.
    public init(body: [UInt8], signature: [UInt8]) throws(OperationEnvelopeError) {
        guard signature.count == TransferBudgets.signatureBytes else { throw .invalidField("signature") }
        guard body.count <= TransferBudgets.operationBodyBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: TransferBudgets.operationBodyBytes))
        }
        self.body = body
        self.signature = signature
    }

    /// The envelope, decoded strictly from the exact body.
    public func envelope() throws(OperationEnvelopeError) -> OperationEnvelope {
        try OperationEnvelope.decode(body: body)
    }
}
