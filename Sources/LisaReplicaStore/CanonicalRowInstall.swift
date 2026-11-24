// One canonical row from Core, as a page or snapshot delivers it (plan §8.4.2 "Row versions", §8.6.4): it is applied
// only if its version is greater than the row's, and it ends the overlays of the operations it contains.

import LisaSyncProtocol

/// A canonical row (or tombstone) to install.
public struct CanonicalRowInstall: Hashable, Sendable {
    public let item: ReplicaItemKey
    /// The commit position of the last change the row reflects.
    public let version: Int64
    /// The row's canonical bytes; `nil` for a tombstone.
    public let body: [UInt8]?
    /// The operations whose effect this state contains; their overlays leave the view when it is installed.
    public let operations: [Identifier128]

    public init(item: ReplicaItemKey, version: Int64, body: [UInt8]?, operations: [Identifier128]) {
        self.item = item
        self.version = version
        self.body = body
        self.operations = operations
    }
}
