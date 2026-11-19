// A wrapper that keeps secrets and private values out of descriptions, interpolation and logs.

/// Wraps a value that must never appear in descriptions, string interpolation or logs.
///
/// The wrapped value stays available through ``revealed`` for code that legitimately needs it, such as an adapter
/// sending a credential to its provider. Encoding keeps the real value so that persistence works; only textual
/// descriptions are redacted.
public struct Sensitive<Value: Sendable>: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The wrapped value. Access it only where the real value is required.
    public let revealed: Value

    public init(_ value: Value) {
        revealed = value
    }

    public var description: String { "<redacted>" }

    public var debugDescription: String { "<redacted>" }
}

extension Sensitive: Equatable where Value: Equatable {}

extension Sensitive: Hashable where Value: Hashable {}

extension Sensitive: Codable where Value: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        revealed = try container.decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(revealed)
    }
}
