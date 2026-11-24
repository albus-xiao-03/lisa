// Why an operation envelope was refused as malformed (plan §8.2.1, §8.2.2, §8.3.2).

/// A malformed operation, refused before any payload is interpreted (`rejected: malformed`).
public enum OperationEnvelopeError: Error, Hashable, Sendable {
    /// The body is not canonical JSON within the operation-body limit.
    case encoding(CanonicalError)
    /// A field is missing, unknown or mistyped.
    case field(CanonicalFieldError)
    /// A field's value breaks its rule (named).
    case invalidField(String)
    /// An unsupported protocol version.
    case unsupportedProtocolVersion(Int64)
    /// A device-signed operation carries `legacyParent` (or a Core legacy child lacks one, or carries a creation
    /// time).
    case legacyMismatch
    /// More than 32 dependencies, a duplicate or unsorted dependency, or a dependency on itself.
    case dependencies
    /// More than 256 explicit observed pieces, or a duplicate or unsorted piece.
    case observedPieces
    /// A `previous` incarnation link on an operation that is not its incarnation's first.
    case incarnationLink
}
