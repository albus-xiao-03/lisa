// The secret-store boundary: every credential is resolved through it, and failures never reveal values.

import LisaRedaction

/// Why a secret could not be resolved. Messages name the reference, never a value.
public enum SecretStoreError: Error, Hashable, Sendable, CustomStringConvertible {
    case notFound(String)
    case unprotectedFile(String)
    case unreadable(String)
    case tooLarge(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .notFound(let reference): "secret \(reference) is not set"
        case .unprotectedFile(let reference): "secret file \(reference) is readable by other users; use mode 0600"
        case .unreadable(let reference): "secret \(reference) could not be read"
        case .tooLarge(let reference): "secret \(reference) is larger than 64 KiB"
        case .unsupported(let reference): "secret \(reference) is not supported by this secret store"
        }
    }
}

/// Resolves secret references. Apple applications use Keychain; headless hosts use environment variables or
/// protected files (SEC-01).
public protocol SecretStore: Sendable {
    func secret(for reference: SecretReference) throws -> Sensitive<String>
}
