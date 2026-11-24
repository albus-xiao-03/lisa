// One change-log entry in a signed change page or snapshot (plan §8.4.2, §8.2.1 "Every decision is also a change-feed
// entry", §8.3.5): an operation's decision at its commit position, with the operation's exact signed bytes, or a
// derived record (an occurrence row or its deletion); either names every partition it touches. A calendar entry names
// the buckets of both its old and its new range, so a move reaches every bucket it left.

/// A change in the change log: an operation's decision, or a derived record.
public struct ChangeEntry: Hashable, Sendable {
    public enum Decision: String, Hashable, Sendable {
        case accepted
        case acceptedWithConflict = "accepted_with_conflict"
        case rejected
    }

    public enum Change: Hashable, Sendable {
        case operation(SignedOperation, Decision)
        case record(DerivedRecord)
    }

    /// The most partitions one entry may name.
    public static let maximumPartitions = 256

    public let position: Int64
    /// Strictly ascending (Unicode scalar order), at least one.
    public let partitions: [String]
    public let change: Change

    public init(position: Int64, partitions: [String], change: Change) throws(OperationEnvelopeError) {
        guard position >= 1 else { throw .invalidField("entry.position") }
        guard !partitions.isEmpty, partitions.count <= Self.maximumPartitions,
            zip(partitions, partitions.dropFirst()).allSatisfy({
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            }), partitions.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 })
        else { throw .invalidField("entry.partitions") }
        self.position = position
        self.partitions = partitions
        self.change = change
    }

    public init(position: Int64, partitions: [String], operation: SignedOperation, decision: Decision)
        throws(OperationEnvelopeError)
    {
        try self.init(position: position, partitions: partitions, change: .operation(operation, decision))
    }

    public init(position: Int64, partitions: [String], record: DerivedRecord) throws(OperationEnvelopeError) {
        try self.init(position: position, partitions: partitions, change: .record(record))
    }

    public var operation: SignedOperation? {
        if case .operation(let operation, _) = change { operation } else { nil }
    }

    public var decision: Decision? {
        if case .operation(_, let decision) = change { decision } else { nil }
    }

    public var record: DerivedRecord? {
        if case .record(let record) = change { record } else { nil }
    }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            var pairs: [(String, CanonicalValue)] = [
                ("position", .integer(position)), ("partitions", .array(partitions.map { .string($0) })),
            ]
            switch change {
            case .operation(let operation, let decision):
                pairs.append(
                    (
                        "operation",
                        .object(
                            try CanonicalObject([
                                ("body", .string(StrictBase64URL.encode(operation.body))),
                                ("signature", .string(StrictBase64URL.encode(operation.signature))),
                            ]))
                    ))
                pairs.append(("decision", .string(decision.rawValue)))
            case .record(let record):
                pairs.append(("record", try record.canonicalValue))
            }
            return .object(try CanonicalObject(pairs))
        }
    }

    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            let partitions = try reader.array("partitions").map { value in
                guard case .string(let name) = value else {
                    throw OperationEnvelopeError.invalidField("entry.partitions")
                }
                return name
            }
            let position = try reader.integer("position")
            let change: Change
            if let record = reader.optionalValue("record") {
                change = .record(try DerivedRecord(canonicalValue: record))
            } else {
                var operation = CanonicalFieldReader(object: try reader.object("operation"))
                let signed = try SignedOperation(
                    body: try operation.bytes("body"), signature: try operation.bytes("signature"))
                try operation.finish()
                guard let decision = Decision(rawValue: try reader.string("decision")) else {
                    throw OperationEnvelopeError.invalidField("entry.decision")
                }
                change = .operation(signed, decision)
            }
            try reader.finish()
            try self.init(position: position, partitions: partitions, change: change)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("entry")
        }
    }
}
