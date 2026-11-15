// The common shape of persisted records: a stable identity, an explicit revision and an update time.

import Foundation

/// A persisted record with a stable identifier and an explicit revision.
public protocol Entity: Codable, Sendable, Identifiable
where ID: Hashable & Codable & Sendable & CustomStringConvertible {
    /// The storage collection that holds records of this type.
    static var collectionName: String { get }
    var id: ID { get }
    var revision: Revision { get set }
    var updatedAt: Date { get set }
}
