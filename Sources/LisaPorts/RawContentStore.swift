// Retained raw source content (message bytes, feed documents), kept apart from records and bounded by retention.

import Foundation

/// A reference to retained raw content.
public struct RawContentRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }
}

/// Stores raw source content. Deleting a source or item removes its content; retention purges old content (DATA-05).
public protocol RawContentStore: Sendable {
    func put(_ data: Data, kind: String, now: Date) throws -> RawContentRef
    func get(_ ref: RawContentRef) throws -> Data?
    func delete(_ ref: RawContentRef) throws
    /// Deletes content stored before `cutoff`; returns how many items were removed.
    @discardableResult
    func purge(storedBefore cutoff: Date) throws -> Int
    /// Deletes the oldest content until at most `budget` bytes remain (OPS-02); returns how many items were removed.
    @discardableResult
    func purge(keepingAtMostBytes budget: Int) throws -> Int
}
