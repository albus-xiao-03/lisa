// The children of one R1 request (plan §8.12.2, "Children are a pure function of the request"). Given the dataset, the
// caller scope, the request ID and the request's changes in request order, every byte of every child is fixed: the
// child ID from its discriminator, the origin (Core's legacy-translation incarnation derived from the request, with
// the index plus one as sequence), the derivation scheme's versions, no creation time, `legacyParent` with the
// complete set's size and digest, and at most one dependency, the immediate predecessor among the request's children
// that touch the same chain (the same entity, or for preferences the same key). Only Core's signature, outside the
// digest, can differ between conversions, so one request converted in two epochs or by two paths yields the same
// children.

import LisaSyncProtocol
import LisaTrust

/// One change an R1 request implies, in request order.
public struct LegacyChange: Hashable, Sendable {
    /// `field:<name>`, `status`, `change:<index>`, `create:task`, … (§8.12.2's table).
    public let discriminator: String
    public let entityType: String
    public let entityID: Identifier128
    /// What orders the children's dependencies: the entity, or for preferences the preference key.
    public let chain: String
    public let operationType: String
    public let payload: CanonicalValue
    /// R1's `expectedRevision` from the request, for a change made against a revision: the child is "observed at
    /// projection revision N" (plan §8.3.2, §8.12.2).
    public let observedRevision: Int64?

    public init(
        discriminator: String, entityType: String, entityID: Identifier128, chain: String, operationType: String,
        payload: CanonicalValue, observedRevision: Int64? = nil
    ) {
        self.discriminator = discriminator
        self.entityType = entityType
        self.entityID = entityID
        self.chain = chain
        self.operationType = operationType
        self.payload = payload
        self.observedRevision = observedRevision
    }
}

/// The derivation scheme `lisa-v1-child-v1`.
public enum LegacyDerivation {
    /// The schema and policy versions every child carries.
    public static let schemaVersion: Int64 = 1
    public static let policyVersion: Int64 = 1

    /// The ID of an entity the request creates, derived like a child ID under `entity:<discriminator>`.
    public static func createdEntityID(
        dataset: Identifier128, scope: String, requestID: String, discriminator: String
    ) -> Identifier128 {
        LegacyChildIdentity.childID(
            dataset: dataset, scope: scope, requestID: requestID, discriminator: "entity:" + discriminator)
    }
}

/// A request's child set before its bodies are encoded (D-74). Every child's ID, the set digest and each child's
/// same-chain predecessor follow from the discriminators and chains alone, so a change R1 refuses before its body
/// could be encoded, a value over the operation's budget say, still has its place in the set. A conversion encodes a
/// child only when it takes the child in.
public struct LegacyChildPlan: Sendable {
    public let datasetID: Identifier128
    public let scope: String
    public let requestID: String
    /// In request order.
    public let changes: [LegacyChange]
    public let childIDs: [Identifier128]
    public let setDigest: Digest256
    let incarnation: Identifier128
    /// Each child's immediate predecessor among the request's children of its chain.
    let predecessors: [Identifier128?]

    /// - Throws: `OperationEnvelopeError` for an empty request or a repeated discriminator.
    public init(datasetID: Identifier128, scope: String, requestID: String, changes: [LegacyChange])
        throws(OperationEnvelopeError)
    {
        guard !changes.isEmpty else { throw .invalidField("legacy.changes") }
        guard Set(changes.map(\.discriminator)).count == changes.count else {
            throw .invalidField("legacy.discriminator")
        }
        let ids = changes.map {
            LegacyChildIdentity.childID(
                dataset: datasetID, scope: scope, requestID: requestID, discriminator: $0.discriminator)
        }
        var lastInChain: [String: Identifier128] = [:]
        var predecessors: [Identifier128?] = []
        for (index, change) in changes.enumerated() {
            predecessors.append(lastInChain[change.chain])
            lastInChain[change.chain] = ids[index]
        }
        self.datasetID = datasetID
        self.scope = scope
        self.requestID = requestID
        self.changes = changes
        childIDs = ids
        setDigest = LegacyChildIdentity.setDigest(orderedChildIDs: ids)
        incarnation = LegacyChildIdentity.incarnationID(dataset: datasetID, scope: scope, requestID: requestID)
        self.predecessors = predecessors
    }

    /// The envelope of the child at `index`.
    /// - Throws: `OperationEnvelopeError` for a field outside its rules.
    public func envelope(at index: Int) throws(OperationEnvelopeError) -> OperationEnvelope {
        let change = changes[index]
        return try OperationEnvelope(
            schemaVersion: LegacyDerivation.schemaVersion, datasetID: datasetID,
            origin: .coreLegacyTranslation(incarnationID: incarnation, sequence: Int64(index) + 1),
            operationID: childIDs[index], entityType: change.entityType, entityID: change.entityID,
            operationType: change.operationType, payload: change.payload,
            dependencies: predecessors[index].map { [$0] } ?? [],
            observed: try change.observedRevision.map { revision throws(OperationEnvelopeError) in
                try ObservedSet(
                    horizon: nil, pieces: [], reviewedSetDigest: nil, group: nil, projectionRevision: revision)
            },
            policyVersion: LegacyDerivation.policyVersion,
            legacyParent: try LegacyParentReference(
                scope: scope, requestID: requestID, discriminator: change.discriminator, index: Int64(index),
                count: Int64(changes.count), setDigest: setDigest),
            createdAt: nil)
    }

    /// The child at `index`, encoded and signed by Core's key.
    public func signed(at index: Int, with core: some MessageSigning) throws -> SignedOperation {
        try OperationSigning.sign(try envelope(at: index), with: core)
    }
}

/// A request's complete child set, unsigned.
public struct LegacyChildSet: Hashable, Sendable {
    public let datasetID: Identifier128
    public let scope: String
    public let requestID: String
    /// In request order.
    public let envelopes: [OperationEnvelope]
    public let setDigest: Digest256

    public var childIDs: [Identifier128] { envelopes.map(\.operationID) }

    /// - Throws: `OperationEnvelopeError` for an empty request, a repeated discriminator, or a field outside its
    ///   rules.
    public init(datasetID: Identifier128, scope: String, requestID: String, changes: [LegacyChange])
        throws(OperationEnvelopeError)
    {
        let plan = try LegacyChildPlan(datasetID: datasetID, scope: scope, requestID: requestID, changes: changes)
        var envelopes: [OperationEnvelope] = []
        for index in changes.indices { envelopes.append(try plan.envelope(at: index)) }
        self.datasetID = datasetID
        self.scope = scope
        self.requestID = requestID
        self.envelopes = envelopes
        setDigest = plan.setDigest
    }

    /// The children signed by Core's key, in request order.
    public func signed(with core: some MessageSigning) throws -> [SignedOperation] {
        try envelopes.map { try OperationSigning.sign($0, with: core) }
    }
}
