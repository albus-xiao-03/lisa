// One change-log entry in a signed change page (plan §8.4.2, §8.2.1 "Every decision is also a change-feed entry"): an
// operation's decision at its commit position, with the operation's exact signed bytes and every partition it
// touches, explicitly named.

/// A decision in the change log.
public struct ChangeEntry: Hashable, Sendable {
    public enum Decision: String, Hashable, Sendable {
        case accepted
        case acceptedWithConflict = "accepted_with_conflict"
        case rejected
    }

    /// The most partitions one entry may name.
    public static let maximumPartitions = 64

    public let position: Int64
    /// Strictly ascending (Unicode scalar order), at least one.
    public let partitions: [String]
    public let operation: SignedOperation
    public let decision: Decision

    public init(position: Int64, partitions: [String], operation: SignedOperation, decision: Decision)
        throws(OperationEnvelopeError)
    {
        guard position >= 1 else { throw .invalidField("entry.position") }
        guard !partitions.isEmpty, partitions.count <= Self.maximumPartitions,
            zip(partitions, partitions.dropFirst()).allSatisfy({
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            }), partitions.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 })
        else { throw .invalidField("entry.partitions") }
        self.position = position
        self.partitions = partitions
        self.operation = operation
        self.decision = decision
    }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            .object(
                try CanonicalObject([
                    ("position", .integer(position)), ("partitions", .array(partitions.map { .string($0) })),
                    (
                        "operation",
                        .object(
                            try CanonicalObject([
                                ("body", .string(StrictBase64URL.encode(operation.body))),
                                ("signature", .string(StrictBase64URL.encode(operation.signature))),
                            ]))
                    ), ("decision", .string(decision.rawValue)),
                ]))
        }
    }

    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            var operation = CanonicalFieldReader(object: try reader.object("operation"))
            let signed = try SignedOperation(
                body: try operation.bytes("body"), signature: try operation.bytes("signature"))
            try operation.finish()
            let partitions = try reader.array("partitions").map { value in
                guard case .string(let name) = value else {
                    throw OperationEnvelopeError.invalidField("entry.partitions")
                }
                return name
            }
            guard let decision = Decision(rawValue: try reader.string("decision")) else {
                throw OperationEnvelopeError.invalidField("entry.decision")
            }
            let position = try reader.integer("position")
            try reader.finish()
            try self.init(position: position, partitions: partitions, operation: signed, decision: decision)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("entry")
        }
    }
}
