// The persistence boundary of the response cache: one stored value per cache key.

import Foundation

/// Durable storage for cached responses. Each key holds one encoded value, and a write replaces it atomically.
public protocol ResponseCacheStorage: Sendable {
    /// The value stored for `key`, or `nil`.
    func read(_ key: CacheKey) throws -> Data?
    /// Stores `data` for `key`, atomically replacing any earlier value.
    func write(_ data: Data, for key: CacheKey) throws
    /// Removes the value for `key`; a missing value is not an error.
    func remove(_ key: CacheKey) throws
    /// Every key with a stored value.
    func keys() throws -> [CacheKey]
    /// Removes every stored value.
    func removeAll() throws
}
