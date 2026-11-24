// Where Core committed a piece (plan §8.3.2, §8.4.2): its epoch, partition and position. A pending piece has none yet.

import LisaSyncProtocol

/// A committed piece's place in Core's change log.
public struct CommitPosition: Hashable, Sendable {
    public let epochID: Identifier128
    public let partition: String
    public let position: Int64

    public init(epochID: Identifier128, partition: String, position: Int64) {
        self.epochID = epochID
        self.partition = partition
        self.position = position
    }
}
