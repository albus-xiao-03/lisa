// What a replica lists for one calendar bucket (plan §8.4.2): an occurrence counts in the bucket when the bucket's own
// proof delivered it at its current version, or when a newer version arrived through another bucket and this one's
// proof hasn't caught up yet. Either way it is shown "as of" the bucket's proved position.

import LisaSyncProtocol

/// One occurrence a bucket lists.
public struct OccurrenceListing: Hashable, Sendable {
    public let id: Identifier128
    public let row: OccurrenceRow
    public let version: Int64
    /// The bucket's proved position: the listing is "as of" it.
    public let asOf: Int64
    /// Whether this bucket's own proof delivered the row at this version; `false` while only another bucket's newer
    /// proof holds it.
    public let provedHere: Bool

    public init(id: Identifier128, row: OccurrenceRow, version: Int64, asOf: Int64, provedHere: Bool) {
        self.id = id
        self.row = row
        self.version = version
        self.asOf = asOf
        self.provedHere = provedHere
    }
}
