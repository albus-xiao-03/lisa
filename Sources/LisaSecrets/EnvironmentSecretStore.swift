// Resolves env:NAME references from the process environment.

import Foundation
import LisaRedaction

/// Reads secrets from environment variables.
public struct EnvironmentSecretStore: SecretStore, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let environment: [String: String]

    /// Uses the current process environment.
    public init() {
        environment = ProcessInfo.processInfo.environment
    }

    /// Uses an explicit environment, for example a sanitized child-process environment.
    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func secret(for reference: SecretReference) throws -> Sensitive<String> {
        guard case .environment(let name) = reference else {
            throw SecretStoreError.unsupported(reference.description)
        }
        guard let value = environment[name], !value.isEmpty else {
            throw SecretStoreError.notFound(reference.description)
        }
        guard value.utf8.count <= 65_536 else { throw SecretStoreError.tooLarge(reference.description) }
        return Sensitive(value)
    }

    /// Never shows a value or a variable name: printing, dumping or mirroring the store reveals nothing.
    public var description: String { "EnvironmentSecretStore(\(environment.count) variables)" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
