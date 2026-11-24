// One owner command as the replica saves it (plan §8.6.1): everything of the operation except what the store
// allocates (operation ID, origin, sequence, creation time) and the dataset.

import LisaSyncProtocol

/// A local change to save.
public struct LocalCommand: Hashable, Sendable {
    public let item: ReplicaItemKey
    public let operationType: String
    public let payload: CanonicalValue
    /// Operation IDs, strictly ascending; at most 32.
    public let dependencies: [Identifier128]
    public let observed: ObservedSet?
    /// The owner's original input (text as typed or spoken), kept with a draft.
    public let originalInput: String?

    public init(
        item: ReplicaItemKey, operationType: String, payload: CanonicalValue, dependencies: [Identifier128] = [],
        observed: ObservedSet? = nil, originalInput: String? = nil
    ) {
        self.item = item
        self.operationType = operationType
        self.payload = payload
        self.dependencies = dependencies
        self.observed = observed
        self.originalInput = originalInput
    }
}
