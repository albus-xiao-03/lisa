// The persistence boundary used by every application service: transactional reads and revision-checked writes.

import Foundation
import LisaDomain

/// Why a store operation failed.
public enum StoreError: Error, Hashable, Sendable, CustomStringConvertible {
    case notFound(collection: String, id: String)
    /// The stored revision differs from the one the caller read (optimistic concurrency).
    case conflict(collection: String, id: String, expected: Revision, actual: Revision)
    /// A unique natural key is already taken.
    case duplicate(collection: String, field: String)
    case unknownField(collection: String, field: String)
    case unknownCollection(String)
    /// The database was written by a newer Lisa; it is never downgraded.
    case schemaTooNew(found: Int, supported: Int)
    case migrationFailed(version: Int, reason: String)
    case corrupt(String)
    case unavailable(String)

    public var description: String {
        switch self {
        case .notFound(let collection, let id): "\(collection) record \(id) does not exist"
        case .conflict(let collection, let id, let expected, let actual):
            "\(collection) record \(id) changed: expected revision \(expected), found \(actual)"
        case .duplicate(let collection, let field): "a \(collection) record with the same \(field) already exists"
        case .unknownField(let collection, let field): "\(collection) has no queryable field \(field)"
        case .unknownCollection(let name): "unknown collection \(name)"
        case .schemaTooNew(let found, let supported):
            "the database uses schema \(found), newer than the supported schema \(supported); it was not opened"
        case .migrationFailed(let version, let reason):
            "migration to schema \(version) failed and was rolled back; the previous data is unchanged (\(reason))"
        case .corrupt(let reason): "the database failed an integrity check: \(reason)"
        case .unavailable(let reason): "the store is unavailable: \(reason)"
        }
    }
}

/// Reads inside a transaction.
public protocol RecordReading {
    func get<E: StoredEntity>(_ type: E.Type, id: E.ID) throws -> E?
    func find<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> [E]
    func count<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> Int
}

/// Writes inside a transaction. Updates require the caller's revision to match the stored one.
public protocol RecordWriting: RecordReading {
    /// Stores a new record at revision 1.
    @discardableResult
    func insert<E: StoredEntity>(_ entity: E) throws -> E
    /// Stores `entity` as revision `entity.revision + 1` if the stored revision equals `entity.revision`.
    @discardableResult
    func update<E: StoredEntity>(_ entity: E) throws -> E
    func delete<E: StoredEntity>(_ type: E.Type, id: E.ID) throws
}

/// The transactional record store.
public protocol RecordStore: Sendable {
    @discardableResult
    func read<T>(_ body: (any RecordReading) throws -> T) throws -> T
    @discardableResult
    func write<T>(_ body: (any RecordWriting) throws -> T) throws -> T
}

extension RecordReading {
    /// The record with `id`, or `StoreError.notFound`.
    public func require<E: StoredEntity>(_ type: E.Type, id: E.ID) throws -> E {
        guard let entity = try get(type, id: id) else {
            throw StoreError.notFound(collection: E.collectionName, id: id.description)
        }
        return entity
    }

    /// The first record matching `query`.
    public func first<E: StoredEntity>(_ type: E.Type, _ query: RecordQuery) throws -> E? {
        try find(type, query.limited(to: 1)).first
    }
}
