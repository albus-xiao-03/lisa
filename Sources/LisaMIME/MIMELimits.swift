// Resource bounds for MIME parsing (OPS-02).

/// Limits applied to every message. A message that exceeds them is rejected or truncated visibly.
public struct MIMELimits: Hashable, Sendable {
    public var maxMessageBytes: Int
    public var maxHeaderBytes: Int
    public var maxHeaderFields: Int
    public var maxDepth: Int
    public var maxParts: Int
    public var maxTextCharacters: Int

    public init(
        maxMessageBytes: Int = 25_000_000, maxHeaderBytes: Int = 262_144, maxHeaderFields: Int = 1_000,
        maxDepth: Int = 10, maxParts: Int = 200, maxTextCharacters: Int = 200_000
    ) {
        self.maxMessageBytes = maxMessageBytes
        self.maxHeaderBytes = maxHeaderBytes
        self.maxHeaderFields = maxHeaderFields
        self.maxDepth = maxDepth
        self.maxParts = maxParts
        self.maxTextCharacters = maxTextCharacters
    }
}

/// A failure that makes a message unusable as a whole.
public enum MIMEError: Error, Hashable, Sendable, CustomStringConvertible {
    case messageTooLarge
    case headersTooLarge
    case noHeaders
    case headerInjection(String)
    case invalidAddress(String)

    public var description: String {
        switch self {
        case .messageTooLarge: "the message exceeds the configured size limit"
        case .headersTooLarge: "the message headers exceed the configured size limit"
        case .noHeaders: "the data does not start with a message header block"
        case .headerInjection(let name): "header \(name) contains a line break"
        // The address itself is private information and is never part of the description.
        case .invalidAddress: "an address is not a valid email address"
        }
    }
}
