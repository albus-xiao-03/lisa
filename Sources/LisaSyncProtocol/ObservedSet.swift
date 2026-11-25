// What an operation that replaces or resolves "what I saw" names (plan §8.3.2): a horizon, explicit pieces, the
// reviewed-set digest of a resolution, and its page in a paged resolution group.

/// Every committed piece of the item and field with commit position ≤ `position` in that epoch and partition.
public struct ObservedHorizon: Hashable, Sendable {
    public let epochID: Identifier128
    public let partition: String
    public let position: Int64

    public init(epochID: Identifier128, partition: String, position: Int64) throws(OperationEnvelopeError) {
        guard WireText.isToken(partition, length: WireText.tokenLength) else {
            throw .invalidField("observed.horizon.partition")
        }
        guard position >= 0 else { throw .invalidField("observed.horizon.position") }
        self.epochID = epochID
        self.partition = partition
        self.position = position
    }
}

/// One page of a paged resolution group: its group, 1-based index, page count and the SHA-256 of the complete
/// sorted list of observed IDs.
public struct ResolutionGroupPage: Hashable, Sendable {
    public let groupID: Identifier128
    public let index: Int64
    public let count: Int64
    public let listDigest: Digest256

    public init(groupID: Identifier128, index: Int64, count: Int64, listDigest: Digest256)
        throws(OperationEnvelopeError)
    {
        guard count >= 1, (1...count).contains(index) else { throw .invalidField("observed.group.index") }
        self.groupID = groupID
        self.index = index
        self.count = count
        self.listDigest = listDigest
    }
}

/// The observed set of an operation.
public struct ObservedSet: Hashable, Sendable {
    /// The most explicit piece IDs one operation may name.
    public static let maximumPieces = 256

    public let horizon: ObservedHorizon?
    /// Pieces seen but not committed by the horizon, strictly ascending.
    public let pieces: [Identifier128]
    /// SHA-256 of the sorted version IDs of every candidate the owner saw, on resolutions.
    public let reviewedSetDigest: Digest256?
    public let group: ResolutionGroupPage?
    /// On a Core-signed legacy child only: R1's `expectedRevision` from the request, "observed at projection revision
    /// N" (plan §8.3.2, §8.12.2). Core maps N to the state that revision reflected when it decides the child. It stands
    /// alone: no horizon, pieces, digest or group beside it.
    public let projectionRevision: Int64?

    public init(
        horizon: ObservedHorizon?, pieces: [Identifier128], reviewedSetDigest: Digest256?, group: ResolutionGroupPage?,
        projectionRevision: Int64? = nil
    ) throws(OperationEnvelopeError) {
        guard pieces.count <= Self.maximumPieces, EnvelopeFields.isStrictlyAscending(pieces) else {
            throw .observedPieces
        }
        if let projectionRevision {
            guard projectionRevision >= 1, horizon == nil, pieces.isEmpty, reviewedSetDigest == nil, group == nil
            else { throw .invalidField("observed.projectionRevision") }
        }
        self.horizon = horizon
        self.pieces = pieces
        self.reviewedSetDigest = reviewedSetDigest
        self.group = group
        self.projectionRevision = projectionRevision
    }

    /// The canonical form, exactly as an envelope's `observed` field carries it. A store that keeps a command before it
    /// can be signed (a draft, plan §8.6.2) keeps its observed set in this form.
    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) { try canonical }
    }

    /// Reads the canonical form with the envelope decoder's rules.
    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        guard case .object(let object) = value else { throw .invalidField("observed") }
        try self.init(canonical: object)
    }

    var canonical: CanonicalValue {
        get throws(CanonicalError) {
            var pairs: [(String, CanonicalValue)] = [("pieces", EnvelopeFields.identifierArray(pieces))]
            if let horizon {
                pairs.append(
                    (
                        "horizon",
                        .object(
                            try CanonicalObject([
                                ("epochID", .string(horizon.epochID.hex)), ("partition", .string(horizon.partition)),
                                ("position", .integer(horizon.position)),
                            ]))
                    ))
            }
            if let reviewedSetDigest { pairs.append(("reviewedSetDigest", .string(reviewedSetDigest.hex))) }
            if let projectionRevision { pairs.append(("projectionRevision", .integer(projectionRevision))) }
            if let group {
                pairs.append(
                    (
                        "group",
                        .object(
                            try CanonicalObject([
                                ("groupID", .string(group.groupID.hex)), ("index", .integer(group.index)),
                                ("count", .integer(group.count)), ("listDigest", .string(group.listDigest.hex)),
                            ]))
                    ))
            }
            return .object(try CanonicalObject(pairs))
        }
    }

    init(canonical object: CanonicalObject) throws(OperationEnvelopeError) {
        var reader = CanonicalFieldReader(object: object)
        do {
            let pieces = try reader.array("pieces")
            guard pieces.count <= Self.maximumPieces else { throw OperationEnvelopeError.observedPieces }
            let ids: [Identifier128]
            do {
                ids = try EnvelopeFields.sortedIdentifiers(pieces, "observed.pieces")
            } catch {
                throw OperationEnvelopeError.observedPieces
            }
            var horizon: ObservedHorizon?
            if let h = try reader.optionalObject("horizon") {
                var hr = CanonicalFieldReader(object: h)
                horizon = try ObservedHorizon(
                    epochID: EnvelopeFields.identifier(hr.string("epochID"), "observed.horizon.epochID"),
                    partition: hr.string("partition"), position: hr.integer("position"))
                try hr.finish()
            }
            let reviewed = try reader.optionalString("reviewedSetDigest").map { (hex) throws(OperationEnvelopeError) in
                try EnvelopeFields.digest(hex, "observed.reviewedSetDigest")
            }
            var group: ResolutionGroupPage?
            if let g = try reader.optionalObject("group") {
                var gr = CanonicalFieldReader(object: g)
                group = try ResolutionGroupPage(
                    groupID: EnvelopeFields.identifier(gr.string("groupID"), "observed.group.groupID"),
                    index: gr.integer("index"), count: gr.integer("count"),
                    listDigest: EnvelopeFields.digest(gr.string("listDigest"), "observed.group.listDigest"))
                try gr.finish()
            }
            let projectionRevision = try reader.optionalInteger("projectionRevision")
            try reader.finish()
            try self.init(
                horizon: horizon, pieces: ids, reviewedSetDigest: reviewed, group: group,
                projectionRevision: projectionRevision)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("observed")
        }
    }
}
