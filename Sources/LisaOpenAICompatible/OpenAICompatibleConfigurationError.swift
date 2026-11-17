// Why an OpenAI-compatible provider could not be configured; descriptions never contain secrets or address paths.

/// A configuration the provider refuses. The description names the problem, never a credential, path or query.
public struct OpenAICompatibleConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}
