// The three kinds of safety for one operation, never confused (plan §8.6.1, R2-SYNC-04): committed in this replica,
// held by peers that signed custody acknowledgements, and committed by Core. Peer custody protects against losing the
// originating device, but it never stands for Core commitment (R2-L15), and the origin never discards an operation
// because of it.

import LisaSyncProtocol

/// Where one journal entry's bytes are safe.
public struct OperationSafety: Hashable, Sendable {
    /// Committed in this replica: "Saved on this device".
    public let savedOnThisDevice: Bool
    /// The peers that acknowledged durably holding these exact bytes, by device ID: "Also held by <device>".
    public let heldBy: [Identifier128]
    /// A final Core acceptance, from a Core receipt or a Core page: "Synced with Core".
    public let syncedWithCore: Bool
    /// The epoch and commit position of that acceptance.
    public let commitEpoch: Identifier128?
    public let commitPosition: Int64?

    public init(
        savedOnThisDevice: Bool, heldBy: [Identifier128], syncedWithCore: Bool, commitEpoch: Identifier128?,
        commitPosition: Int64?
    ) {
        self.savedOnThisDevice = savedOnThisDevice
        self.heldBy = heldBy
        self.syncedWithCore = syncedWithCore
        self.commitEpoch = commitEpoch
        self.commitPosition = commitPosition
    }
}
