// The R2 operation envelope (plan §8.2.1): its fields, consistency rules, canonical encoding and strict decoding.

/// One operation, before signing. Its canonical bytes are the signed body; the digest and the signature are computed
/// over exactly those bytes (LisaTrust), and nothing re-encodes them.
///
/// Rules checked here (`rejected: malformed` otherwise): protocol version 2; a device operation has a creation time
/// and no `legacyParent`; a Core legacy child has `legacyParent` and no creation time; at most 32 dependencies,
/// strictly ascending and never the operation itself; at most 256 explicit observed pieces; the incarnation link only
/// on sequence 1; known operation and entity types; no unknown fields; the whole body within 64 KiB.
public struct OperationEnvelope: Hashable, Sendable {
    public static let protocolVersion: Int64 = 2

    public let schemaVersion: Int64
    public let datasetID: Identifier128
    public let origin: OperationOrigin
    public let operationID: Identifier128
    public let entityType: String
    public let entityID: Identifier128
    public let operationType: String
    public let payload: CanonicalValue
    /// Strictly ascending; at most 32.
    public let dependencies: [Identifier128]
    public let observed: ObservedSet?
    public let policyVersion: Int64
    public let legacyParent: LegacyParentReference?
    /// Unix milliseconds, for display and audit only; absent on legacy children.
    public let createdAt: Int64?

    public init(
        schemaVersion: Int64, datasetID: Identifier128, origin: OperationOrigin, operationID: Identifier128,
        entityType: String, entityID: Identifier128, operationType: String, payload: CanonicalValue,
        dependencies: [Identifier128], observed: ObservedSet?, policyVersion: Int64,
        legacyParent: LegacyParentReference?, createdAt: Int64?
    ) throws(OperationEnvelopeError) {
        guard schemaVersion >= 1 else { throw .invalidField("schemaVersion") }
        guard policyVersion >= 1 else { throw .invalidField("policyVersion") }
        guard OperationCatalog.operationTypes.contains(operationType) else { throw .invalidField("type") }
        guard OperationCatalog.entityTypes.contains(entityType) else { throw .invalidField("entity.type") }
        guard dependencies.count <= TransferBudgets.maximumDependencies,
            EnvelopeFields.isStrictlyAscending(dependencies), !dependencies.contains(operationID)
        else { throw .dependencies }
        switch origin {
        case .device:
            guard legacyParent == nil, createdAt != nil else { throw .legacyMismatch }
        case .coreLegacyTranslation:
            guard legacyParent != nil, createdAt == nil else { throw .legacyMismatch }
        }
        if let createdAt, createdAt < 0 { throw .invalidField("createdAt") }
        self.schemaVersion = schemaVersion
        self.datasetID = datasetID
        self.origin = origin
        self.operationID = operationID
        self.entityType = entityType
        self.entityID = entityID
        self.operationType = operationType
        self.payload = payload
        self.dependencies = dependencies
        self.observed = observed
        self.policyVersion = policyVersion
        self.legacyParent = legacyParent
        self.createdAt = createdAt
    }

    /// The canonical signed body.
    /// - Throws: `OperationEnvelopeError.encoding` when the body exceeds 64 KiB or nests too deeply.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            return try CanonicalEncoder.encode(.object(try canonicalObject()), limits: .operationBody)
        } catch {
            throw .encoding(error)
        }
    }

    func canonicalObject() throws(CanonicalError) -> CanonicalObject {
        var pairs: [(String, CanonicalValue)] = [
            ("protocolVersion", .integer(Self.protocolVersion)), ("schemaVersion", .integer(schemaVersion)),
            ("datasetID", .string(datasetID.hex)), ("origin", try origin.canonical),
            ("operationID", .string(operationID.hex)),
            ("entity", .object(try CanonicalObject([("type", .string(entityType)), ("id", .string(entityID.hex))]))),
            ("type", .string(operationType)), ("payload", payload),
            ("dependencies", EnvelopeFields.identifierArray(dependencies)), ("policyVersion", .integer(policyVersion)),
        ]
        if let observed { pairs.append(("observed", try observed.canonical)) }
        if let legacyParent { pairs.append(("legacyParent", try legacyParent.canonical)) }
        if let createdAt { pairs.append(("createdAt", .integer(createdAt))) }
        return try CanonicalObject(pairs)
    }

    /// Decodes a signed body strictly: canonical JSON within 64 KiB, then every envelope rule.
    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> OperationEnvelope {
        let value: CanonicalValue
        do {
            value = try CanonicalDecoder.decode(body, limits: .operationBody)
        } catch {
            throw .encoding(error)
        }
        guard case .object(let object) = value else { throw .field(.notAnObject) }
        var reader = CanonicalFieldReader(object: object)
        do {
            let version = try reader.integer("protocolVersion")
            guard version == protocolVersion else { throw OperationEnvelopeError.unsupportedProtocolVersion(version) }
            let entity = try reader.object("entity")
            var entityReader = CanonicalFieldReader(object: entity)
            let entityType = try entityReader.string("type")
            let entityID = try EnvelopeFields.identifier(entityReader.string("id"), "entity.id")
            try entityReader.finish()
            let dependencies: [Identifier128]
            let rawDependencies = try reader.array("dependencies")
            guard rawDependencies.count <= TransferBudgets.maximumDependencies else {
                throw OperationEnvelopeError.dependencies
            }
            do {
                dependencies = try EnvelopeFields.sortedIdentifiers(rawDependencies, "dependencies")
            } catch {
                throw OperationEnvelopeError.dependencies
            }
            let envelope = try OperationEnvelope(
                schemaVersion: reader.integer("schemaVersion"),
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "datasetID"),
                origin: OperationOrigin(canonical: reader.object("origin")),
                operationID: EnvelopeFields.identifier(reader.string("operationID"), "operationID"),
                entityType: entityType, entityID: entityID, operationType: reader.string("type"),
                payload: reader.value("payload"), dependencies: dependencies,
                observed: reader.optionalObject("observed").map { (o) throws(OperationEnvelopeError) in
                    try ObservedSet(canonical: o)
                },
                policyVersion: reader.integer("policyVersion"),
                legacyParent: reader.optionalObject("legacyParent").map { (o) throws(OperationEnvelopeError) in
                    try LegacyParentReference(canonical: o)
                },
                createdAt: reader.optionalInteger("createdAt"))
            try reader.finish()
            return envelope
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("envelope")
        }
    }
}
