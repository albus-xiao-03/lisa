// Explicit revisions for mutable records, used for optimistic concurrency and conflict detection.

/// A monotonically increasing revision number. A new record starts at revision 1.
public struct Revision: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }

    /// The revision of a newly created record.
    public static let initial = Revision(1)

    /// The revision after this one.
    public var next: Revision { Revision(value + 1) }

    public var description: String { String(value) }

    public static func < (lhs: Revision, rhs: Revision) -> Bool {
        lhs.value < rhs.value
    }

    public init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
