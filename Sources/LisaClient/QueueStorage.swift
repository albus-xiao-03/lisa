// The persistence boundary of the offline queue: load every entry, and replace every entry atomically.

import Foundation

/// Durable storage for the offline queue.
///
/// The queue saves its complete state after every change. A conforming store must replace the stored entries
/// atomically, so that a crash leaves either the previous state or the new one, and must keep the entries' order.
public protocol QueueStorage: Sendable {
    /// The stored entries in queue order; an empty list when nothing is stored.
    func load() throws -> [QueuedRequest]
    /// Replaces the stored entries with `entries`, atomically.
    func save(_ entries: [QueuedRequest]) throws
}
