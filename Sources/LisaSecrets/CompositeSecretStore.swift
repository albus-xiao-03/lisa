// Routes each secret reference to the store that handles its kind.

import LisaRedaction

/// Dispatches environment, file and Keychain references to their stores. A missing Keychain store reports the
/// reference as unsupported instead of falling back to anything weaker.
public struct CompositeSecretStore: SecretStore {
    private let environment: any SecretStore
    private let files: any SecretStore
    private let keychain: (any SecretStore)?

    public init(
        environment: any SecretStore = EnvironmentSecretStore(), files: any SecretStore = ProtectedFileSecretStore(),
        keychain: (any SecretStore)? = nil
    ) {
        self.environment = environment
        self.files = files
        self.keychain = keychain
    }

    public func secret(for reference: SecretReference) throws -> Sensitive<String> {
        switch reference {
        case .environment: return try environment.secret(for: reference)
        case .file: return try files.secret(for: reference)
        case .keychain:
            guard let keychain else { throw SecretStoreError.unsupported(reference.description) }
            return try keychain.secret(for: reference)
        }
    }
}
