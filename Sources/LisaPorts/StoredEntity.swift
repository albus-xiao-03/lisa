// Entities that the record store can persist: each declares its indexed fields and unique natural keys.

import Foundation
import LisaDomain

/// An indexed column of an entity collection.
public struct IndexDefinition: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case text = "TEXT"
        case integer = "INTEGER"
    }

    public var name: String
    public var kind: Kind
    /// A unique natural key: storing a second record with the same non-null value fails as a duplicate.
    public var unique: Bool

    public init(_ name: String, _ kind: Kind, unique: Bool = false) {
        self.name = name
        self.kind = kind
        self.unique = unique
    }
}

/// A persistable entity. `id`, `revision` and `updated_at` are always queryable in addition to `indexes`.
public protocol StoredEntity: Entity {
    static var indexes: [IndexDefinition] { get }
    /// The current value of every declared index.
    var indexValues: [String: IndexValue] { get }
}

extension StoredEntity {
    /// Field names that queries may use for this entity.
    public static var queryableFields: Set<String> {
        Set(indexes.map(\.name) + ["id", "revision", "updated_at"])
    }
}
