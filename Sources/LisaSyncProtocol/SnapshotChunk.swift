// One chunk of a full snapshot (plan §8.4.3, §8.6.3): a page of the Core-signed paged artifact of type `snapshot`,
// whose version is the cut. It holds committed operations of the partitions the snapshot covers, each as a
// change-log entry at its commit position; every chunk names the same partitions, the snapshot's coverage.

/// A verified snapshot page's content.
public struct SnapshotChunk: Hashable, Sendable {
    /// The paged artifact type of a full snapshot.
    public static let artifactType = "snapshot"

    /// Strictly ascending; the partitions the snapshot covers.
    public let partitions: [String]
    /// Committed operations, strictly ascending by position.
    public let entries: [ChangeEntry]

    public init(partitions: [String], entries: [ChangeEntry]) throws(OperationEnvelopeError) {
        guard !partitions.isEmpty,
            zip(partitions, partitions.dropFirst()).allSatisfy({
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            })
        else { throw .invalidField("chunk.partitions") }
        guard zip(entries, entries.dropFirst()).allSatisfy({ $0.position < $1.position }),
            entries.allSatisfy({ $0.decision != .rejected && !Set(partitions).isDisjoint(with: $0.partitions) })
        else { throw .invalidField("chunk.entries") }
        self.partitions = partitions
        self.entries = entries
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            var values: [CanonicalValue] = []
            for entry in entries { values.append(try entry.canonicalValue) }
            let object = try CanonicalObject([
                ("partitions", .array(partitions.map { .string($0) })), ("entries", .array(values)),
            ])
            return try CanonicalEncoder.encode(
                .object(object), limits: CanonicalLimits(maxBytes: PagedArtifactHeader.maximumPageBytes))
        } catch {
            throw .encoding(error)
        }
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> SnapshotChunk {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: PagedArtifactHeader.maximumPageBytes)))
            let partitions = try reader.array("partitions").map { value in
                guard case .string(let name) = value else {
                    throw OperationEnvelopeError.invalidField("chunk.partitions")
                }
                return name
            }
            let entries = try reader.array("entries").map { try ChangeEntry(canonicalValue: $0) }
            try reader.finish()
            return try SnapshotChunk(partitions: partitions, entries: entries)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("chunk")
        }
    }
}
