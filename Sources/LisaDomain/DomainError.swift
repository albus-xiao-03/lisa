// Errors raised by domain validation and state transitions.

/// A rule in the domain model rejected an operation.
public enum DomainError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A state transition that the entity's lifecycle does not allow.
    case invalidTransition(entity: String, from: String, to: String)
    /// A field value outside its permitted range or format.
    case invalidValue(field: String, reason: String)
    /// The principal is not allowed to perform the operation.
    case notPermitted(String)
    /// The record changed since the caller read it.
    case revisionConflict(expected: Revision, actual: Revision)

    public var description: String {
        switch self {
        case .invalidTransition(let entity, let from, let to): "\(entity) cannot move from \(from) to \(to)"
        case .invalidValue(let field, let reason): "invalid \(field): \(reason)"
        case .notPermitted(let reason): "not permitted: \(reason)"
        case .revisionConflict(let expected, let actual): "revision conflict: expected \(expected), found \(actual)"
        }
    }
}
