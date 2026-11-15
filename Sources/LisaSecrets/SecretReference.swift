// References to secrets held outside configuration and the database: env:NAME, file:/path or keychain:service/account.

/// Where a secret lives. Configuration stores only these references, never the secret values.
public enum SecretReference: Hashable, Sendable, CustomStringConvertible {
    /// An environment variable.
    case environment(String)
    /// A protected file readable only by the owner.
    case file(String)
    /// An Apple Keychain item, resolved only by the Apple applications.
    case keychain(service: String, account: String)

    /// Parses `env:NAME`, `file:/absolute/path` or `keychain:service/account`.
    public init?(_ text: String) {
        if text.hasPrefix("env:") {
            let name = String(text.dropFirst(4))
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
            self = .environment(name)
        } else if text.hasPrefix("file:") {
            let path = String(text.dropFirst(5))
            guard path.hasPrefix("/"), !path.contains("\u{0}") else { return nil }
            self = .file(path)
        } else if text.hasPrefix("keychain:") {
            let parts = text.dropFirst(9).split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            self = .keychain(service: parts[0], account: parts[1])
        } else {
            return nil
        }
    }

    /// The reference in its textual form. It names a location, not a value, so it is safe to show.
    public var description: String {
        switch self {
        case .environment(let name): "env:\(name)"
        case .file(let path): "file:\(path)"
        case .keychain(let service, let account): "keychain:\(service)/\(account)"
        }
    }
}

extension SecretReference: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let reference = SecretReference(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected env:NAME, file:/path or keychain:service/account")
        }
        self = reference
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
