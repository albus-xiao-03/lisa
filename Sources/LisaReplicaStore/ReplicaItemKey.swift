// One item of the replica: an operation's entity type and ID (plan §8.2.1).

import LisaSyncProtocol

/// The item an operation, draft, canonical row or index entry is about.
public struct ReplicaItemKey: Hashable, Sendable {
    public let entityType: String
    public let entityID: Identifier128

    public init(entityType: String, entityID: Identifier128) {
        self.entityType = entityType
        self.entityID = entityID
    }
}
