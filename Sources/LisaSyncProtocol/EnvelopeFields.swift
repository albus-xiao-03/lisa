// Field conversions shared by the envelope types (plan §8.2.1): identifiers, digests and sorted ID lists.

/// Typed field parsing for envelope types, mapping every failure to `OperationEnvelopeError.invalidField`.
enum EnvelopeFields {
    static func identifier(_ hex: String, _ field: String) throws(OperationEnvelopeError) -> Identifier128 {
        guard let value = try? Identifier128(hex: hex) else { throw .invalidField(field) }
        return value
    }

    static func digest(_ hex: String, _ field: String) throws(OperationEnvelopeError) -> Digest256 {
        guard let value = try? Digest256(hex: hex) else { throw .invalidField(field) }
        return value
    }

    /// A strictly ascending list of identifiers (ascending by their hexadecimal text, which is bytewise order).
    static func sortedIdentifiers(_ values: [CanonicalValue], _ field: String) throws(OperationEnvelopeError)
        -> [Identifier128]
    {
        var out: [Identifier128] = []
        for value in values {
            guard case .string(let hex) = value else { throw .invalidField(field) }
            let id = try identifier(hex, field)
            if let last = out.last, !last.bytes.lexicographicallyPrecedes(id.bytes) { throw .invalidField(field) }
            out.append(id)
        }
        return out
    }

    static func isStrictlyAscending(_ ids: [Identifier128]) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0.bytes.lexicographicallyPrecedes($1.bytes) }
    }

    static func identifierArray(_ ids: [Identifier128]) -> CanonicalValue {
        .array(ids.map { .string($0.hex) })
    }
}
