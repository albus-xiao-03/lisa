// The reference a Core-signed legacy child carries to its R1 request (plan §8.2.1, §8.12.2).

/// `legacyParent {scope, requestID, discriminator, index, count, setDigest}`: the R1 caller scope and request ID, the
/// child's discriminator (for example `change:3`), its index in the complete child set, the set's size, and the
/// SHA-256 of the ordered child IDs. R1's fingerprint stays in Core's parent and is never replicated.
public struct LegacyParentReference: Hashable, Sendable {
    public let scope: String
    public let requestID: String
    public let discriminator: String
    public let index: Int64
    public let count: Int64
    public let setDigest: Digest256

    /// - Throws: `OperationEnvelopeError.invalidField` for a token outside its alphabet or length, or an index outside
    ///   `0..<count`.
    public init(
        scope: String, requestID: String, discriminator: String, index: Int64, count: Int64, setDigest: Digest256
    ) throws(OperationEnvelopeError) {
        guard WireText.isToken(scope, length: WireText.tokenLength) else { throw .invalidField("legacyParent.scope") }
        guard WireText.isToken(requestID, length: WireText.requestIDLength) else {
            throw .invalidField("legacyParent.requestID")
        }
        guard WireText.isToken(discriminator, length: WireText.tokenLength) else {
            throw .invalidField("legacyParent.discriminator")
        }
        guard count >= 1, (0..<count).contains(index) else { throw .invalidField("legacyParent.index") }
        self.scope = scope
        self.requestID = requestID
        self.discriminator = discriminator
        self.index = index
        self.count = count
        self.setDigest = setDigest
    }

    var canonical: CanonicalValue {
        get throws(CanonicalError) {
            .object(
                try CanonicalObject([
                    ("scope", .string(scope)), ("requestID", .string(requestID)),
                    ("discriminator", .string(discriminator)), ("index", .integer(index)), ("count", .integer(count)),
                    ("setDigest", .string(setDigest.hex)),
                ]))
        }
    }

    init(canonical object: CanonicalObject) throws(OperationEnvelopeError) {
        var reader = CanonicalFieldReader(object: object)
        do {
            try self.init(
                scope: reader.string("scope"), requestID: reader.string("requestID"),
                discriminator: reader.string("discriminator"), index: reader.integer("index"),
                count: reader.integer("count"),
                setDigest: EnvelopeFields.digest(reader.string("setDigest"), "legacyParent.setDigest"))
            try reader.finish()
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("legacyParent")
        }
    }
}
