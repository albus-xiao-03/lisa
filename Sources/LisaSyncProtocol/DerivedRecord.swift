// A derived record in a change-log entry (plan §8.3.5, §8.4.2): a row Core computed — a calendar occurrence — or its
// deletion. It is not an operation and carries no signature of its own: the Core-signed page or snapshot vouches for
// it. Deletions are entries too, so absence is proved like any other change.

/// One derived row, or its deletion.
public struct DerivedRecord: Hashable, Sendable {
    public static let types: Set<String> = ["occurrence"]

    public let type: String
    public let id: Identifier128
    /// The row's canonical value; `nil` for a deletion.
    public let row: CanonicalValue?

    public init(type: String, id: Identifier128, row: CanonicalValue?) throws(OperationEnvelopeError) {
        guard Self.types.contains(type) else { throw .invalidField("record.type") }
        if type == "occurrence", let row { _ = try OccurrenceRow(canonicalValue: row) }
        self.type = type
        self.id = id
        self.row = row
    }

    /// The occurrence it carries, if it is one and not a deletion.
    public var occurrence: OccurrenceRow? {
        guard type == "occurrence", let row else { return nil }
        return try? OccurrenceRow(canonicalValue: row)
    }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            .object(
                try CanonicalObject([("type", .string(type)), ("id", .string(id.hex)), ("row", row ?? .null)]))
        }
    }

    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            let type = try reader.string("type")
            let id = try EnvelopeFields.identifier(reader.string("id"), "record.id")
            let row = try reader.value("row")
            try reader.finish()
            if case .null = row {
                try self.init(type: type, id: id, row: nil)
            } else {
                try self.init(type: type, id: id, row: row)
            }
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("record")
        }
    }
}
