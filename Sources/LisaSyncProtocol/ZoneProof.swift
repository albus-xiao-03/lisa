// Core's proof that a source's occurrences were re-expanded for a planning zone (plan §8.4.2 "Source time evidence and
// coverage"): for this source, zone generation and these buckets, the replica holds every occurrence that could fall
// there, so a zone-unverified mark clears for them. A partial refresh publishes no proof.

/// A zone proof for one source over a bucket range.
public struct ZoneProof: Hashable, Sendable {
    public let sourceID: String
    public let zone: String
    public let generation: Int64
    public let buckets: ClosedRange<Int64>

    public init(sourceID: String, zone: String, generation: Int64, buckets: ClosedRange<Int64>)
        throws(OperationEnvelopeError)
    {
        guard !sourceID.isEmpty, !zone.isEmpty, zone.utf8.count <= 64, generation >= 1 else {
            throw .invalidField("zoneProof")
        }
        self.sourceID = sourceID
        self.zone = zone
        self.generation = generation
        self.buckets = buckets
    }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            .object(
                try CanonicalObject([
                    ("sourceID", .string(sourceID)), ("zone", .string(zone)), ("generation", .integer(generation)),
                    ("firstBucket", .integer(buckets.lowerBound)), ("lastBucket", .integer(buckets.upperBound)),
                ]))
        }
    }

    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            let first = try reader.integer("firstBucket")
            let last = try reader.integer("lastBucket")
            guard last >= first else { throw OperationEnvelopeError.invalidField("zoneProof.buckets") }
            let proof = try ZoneProof(
                sourceID: try reader.string("sourceID"), zone: try reader.string("zone"),
                generation: try reader.integer("generation"), buckets: first...last)
            try reader.finish()
            self = proof
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("zoneProof")
        }
    }
}
