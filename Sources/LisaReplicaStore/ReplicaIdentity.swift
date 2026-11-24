// Who a replica is (plan §8.1.1, §8.6.2): its installation from creation, and its dataset and device once enrolled.

import LisaSyncProtocol

/// The replica's identity.
public struct ReplicaIdentity: Hashable, Sendable {
    /// Random, created with the replica; never copied to another installation's replica.
    public let installationID: Identifier128
    public let datasetID: Identifier128?
    public let deviceID: Identifier128?
    /// Unix milliseconds.
    public let createdAt: Int64

    public init(installationID: Identifier128, datasetID: Identifier128?, deviceID: Identifier128?, createdAt: Int64) {
        self.installationID = installationID
        self.datasetID = datasetID
        self.deviceID = deviceID
        self.createdAt = createdAt
    }

    /// Whether operations can be created: the dataset and this device's ID are known.
    public var isEnrolled: Bool { datasetID != nil && deviceID != nil }
}
