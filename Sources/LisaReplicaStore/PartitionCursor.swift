// A replica's cursor for one partition (plan §8.4.2): the epoch and position through which the partition is proved,
// and whether a repair is running. A cursor never moves backward within an epoch.

import LisaSyncProtocol

/// One partition's cursor.
public struct PartitionCursor: Hashable, Sendable {
    public let partition: String
    public let epochID: Identifier128
    public let position: Int64
    public let isRepairing: Bool

    public init(partition: String, epochID: Identifier128, position: Int64, isRepairing: Bool) {
        self.partition = partition
        self.epochID = epochID
        self.position = position
        self.isRepairing = isRepairing
    }
}
