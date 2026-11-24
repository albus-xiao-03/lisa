// The replica store's settings (plan §8.6.1, §8.15.1, §8.15.2), each with its default.

/// How a replica store builds operations and keeps its reserve.
public struct ReplicaStoreConfiguration: Hashable, Sendable {
    /// The envelope's schema version for operations this replica creates.
    public var schemaVersion: Int64
    /// The policy version operations this replica creates declare.
    public var policyVersion: Int64
    /// The capture reserve and ballast size (§8.15.2): 64 MiB on clients.
    public var captureReserveBytes: Int
    /// How often the reader monitor samples while long readers are active (§8.15.2): every second; `nil` leaves
    /// sampling to explicit `readers.sample()` calls.
    public var readerSampleInterval: Duration?

    public init(
        schemaVersion: Int64 = 1, policyVersion: Int64 = 1, captureReserveBytes: Int = 64 << 20,
        readerSampleInterval: Duration? = .seconds(1)
    ) {
        self.schemaVersion = schemaVersion
        self.policyVersion = policyVersion
        self.captureReserveBytes = captureReserveBytes
        self.readerSampleInterval = readerSampleInterval
    }
}
