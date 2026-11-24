// The duplicate rules every holder applies, Core and replicas alike, with no exception (plan §8.2.1, R2-SYNC-02).

/// What a holder already knows about an operation identity: its ID, the digest of its body and, for a device
/// operation, its origin triple.
public struct KnownOperation: Hashable, Sendable {
    public let operationID: Identifier128
    public let digest: Digest256
    public let originTriple: OriginTriple?

    public init(operationID: Identifier128, digest: Digest256, originTriple: OriginTriple?) {
        self.operationID = operationID
        self.digest = digest
        self.originTriple = originTriple
    }
}

/// `(device, incarnation, sequence)`.
public struct OriginTriple: Hashable, Sendable {
    public let device: Identifier128
    public let incarnation: Identifier128
    public let sequence: Int64

    public init(device: Identifier128, incarnation: Identifier128, sequence: Int64) {
        self.device = device
        self.incarnation = incarnation
        self.sequence = sequence
    }
}

/// The outcome of comparing an arriving operation with what the holder knows.
public enum OperationIdentityVerdict: Hashable, Sendable {
    /// Never seen: decide it normally.
    case new
    /// Same ID and digest: answer with the current receipt.
    case duplicate
    /// Same ID, different digest: `rejected: identity_reuse` and a security event.
    case identityReuse
    /// The same `(device, incarnation, sequence)` under another ID: `rejected: sequence_reuse` and a security event.
    case sequenceReuse
}

/// Applies the three duplicate rules in their order.
public enum OperationIdentityCheck {
    /// - Parameters:
    ///   - byID: the known operation with the arriving ID, if any.
    ///   - byOrigin: the known operation with the arriving origin triple, if any.
    public static func verdict(
        arrivingID: Identifier128, arrivingDigest: Digest256, byID: KnownOperation?, byOrigin: KnownOperation?
    ) -> OperationIdentityVerdict {
        if let known = byID {
            return known.digest == arrivingDigest ? .duplicate : .identityReuse
        }
        if let known = byOrigin, known.operationID != arrivingID { return .sequenceReuse }
        return .new
    }
}
