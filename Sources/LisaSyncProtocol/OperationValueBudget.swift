// Value sizes derived from the encoded operation (plan §8.3.3).

/// The largest encoded value an operation of a type can carry so that its whole canonical body stays within 64 KiB.
///
/// `maximumValueBytes(type)` = 65,536 − the encoded size of that type's largest envelope whose payload is
/// `{"value":""}`: every optional field at its maximum (32 dependencies, 256 observed pieces with a horizon, a
/// reviewed-set digest and a group page, the device origin with its incarnation link, or, for the legacy origin, a
/// `legacyParent` with 128-character tokens), the longest entity type and the largest integers. The value's own
/// encoded bytes — after canonical escaping, quotes excluded — must fit in what remains. Payload schemas with more
/// fields than `value` subtract their own encoded overhead when they are defined.
public enum OperationValueBudget {
    /// The largest encoded value, in bytes, for operations of `type`.
    public static func maximumValueBytes(type: String) throws(OperationEnvelopeError) -> Int {
        let envelopes = try [largestEnvelope(type: type, legacy: false), largestEnvelope(type: type, legacy: true)]
        var largest = 0
        for envelope in envelopes {
            let object: CanonicalObject
            do {
                object = try envelope.canonicalObject()
                largest = max(largest, try CanonicalEncoder.encodedLength(of: .object(object)))
            } catch {
                throw .encoding(error)
            }
        }
        return TransferBudgets.operationBodyBytes - largest
    }

    static func largestEnvelope(type: String, legacy: Bool) throws(OperationEnvelopeError) -> OperationEnvelope {
        let id = Identifier128(uncheckedBytes: Array(repeating: 0xFF, count: 16))
        let digest = try? Digest256(bytes: Array(repeating: 0xFF, count: 32))
        guard let digest else { throw .invalidField("digest") }
        let ids = (0..<UInt8(32)).map { Identifier128(uncheckedBytes: Array(repeating: 0, count: 15) + [$0]) }
        let pieces = (0..<256).map { n in
            Identifier128(uncheckedBytes: Array(repeating: 0, count: 14) + [UInt8(n >> 8), UInt8(n & 0xFF)])
        }
        let longToken = String(repeating: "x", count: 128)
        let origin: OperationOrigin =
            legacy
            ? .coreLegacyTranslation(incarnationID: id, sequence: .max)
            : .device(
                deviceID: id, incarnationID: id, sequence: 1,
                previous: try IncarnationLink(incarnationID: id, lastSequence: .max))
        let parent =
            legacy
            ? try LegacyParentReference(
                scope: longToken, requestID: longToken, discriminator: longToken, index: .max - 1, count: .max,
                setDigest: digest)
            : nil
        return try OperationEnvelope(
            schemaVersion: .max, datasetID: id, origin: origin,
            operationID: Identifier128(
                uncheckedBytes: Array(repeating: 0xEE, count: 16)), entityType: OperationCatalog.longestEntityType,
            entityID: id, operationType: type,
            payload: .object((try? CanonicalObject([("value", .string(""))])) ?? .empty), dependencies: ids,
            observed: try ObservedSet(
                horizon: try ObservedHorizon(epochID: id, partition: longToken, position: .max), pieces: pieces,
                reviewedSetDigest: digest,
                group: try ResolutionGroupPage(groupID: id, index: .max, count: .max, listDigest: digest)),
            policyVersion: .max, legacyParent: parent, createdAt: legacy ? nil : .max)
    }
}
