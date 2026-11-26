// Full snapshots from Core (plan §8.4.3, §8.6.3): one consistent cut on a read transaction; every accepted operation of
// the named partitions at or below it, in position order, as change-log entries in `SnapshotChunk`s, rejections left
// out as the format requires; a paged artifact of type `snapshot`, Merkle-bound, whose header Core signs with the cut
// as its version. A chunk that would pass a page's 512 KiB carries fewer entries.

import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// A signed full snapshot: the header Core signed and its pages, each with its inclusion proof.
public struct CoreSnapshot: Hashable, Sendable {
    public let headerBody: [UInt8]
    public let headerSignature: [UInt8]
    public let pages: [PagedArtifactPage]
    /// The cut: the newest commit position the snapshot reflects.
    public let cut: Int64
}

extension CoreLedger {
    /// A full snapshot of `partitions` at the newest commit position.
    public func snapshot(partitions: [String], entriesPerChunk: Int = 256) throws(CoreLedgerError) -> CoreSnapshot {
        let names = partitions.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
        let (epoch, cut, entries): (Identifier128, Int64, [ChangeEntry]) = try read { session, _ in
            guard
                let row = try session.query(
                    "SELECT epoch_id, last_position FROM core_dataset WHERE singleton = 1"
                ).first
            else { throw CoreLedgerError.corrupt("the dataset row") }
            let epoch = try CoreColumns.identifier(row[0])
            let cut = try CoreColumns.integer(row[1])
            let placeholders = Array(repeating: "?", count: names.count).joined(separator: ", ")
            let rows = try session.query(
                """
                SELECT c.position, c.decision, c.partitions, o.body, o.signature, o.observed_epoch, o.observed_position
                FROM core_change_log c JOIN core_operations o ON o.operation_id = c.operation_id
                WHERE c.position <= ? AND c.decision != 'rejected' AND c.partitions IN (\(placeholders))
                ORDER BY c.position
                """, [.integer(cut)] + names.map { .text($0) })
            let entries = try rows.map { row in
                guard let decision = ChangeEntry.Decision(rawValue: try CoreColumns.text(row[1])) else {
                    throw CoreLedgerError.corrupt("a change-log decision")
                }
                return try ChangeEntry(
                    position: try CoreColumns.integer(row[0]), partitions: [try CoreColumns.text(row[2])],
                    operation: try SignedOperation(
                        body: try CoreColumns.bytes(row[3]), signature: try CoreColumns.bytes(row[4])),
                    decision: decision,
                    observedHorizon: try CoreTaskFold.resolvedHorizon(
                        epoch: row[5], position: row[6], partition: try CoreColumns.text(row[2])))
            }
            return (epoch, cut, entries)
        }
        var chunks: [[UInt8]] = []
        do {
            if entries.isEmpty { chunks.append(try SnapshotChunk(partitions: names, entries: []).canonicalBody()) }
            var start = 0
            while start < entries.count {
                var count = min(max(1, entriesPerChunk), entries.count - start)
                while true {
                    do {
                        chunks.append(
                            try SnapshotChunk(partitions: names, entries: Array(entries[start..<start + count]))
                                .canonicalBody())
                        break
                    } catch  where count > 1 {
                        count /= 2
                    }
                }
                start += count
            }
        } catch {
            throw .encodingFailed(String(describing: error))
        }
        let header: PagedArtifactHeader
        let pages: [PagedArtifactPage]
        do {
            (header, pages) = try PagedArtifactVerification.paginate(
                chunks, artifactType: SnapshotChunk.artifactType, dataset: datasetID, epoch: epoch, version: cut)
        } catch {
            throw .encodingFailed(String(describing: error))
        }
        do {
            let signed = try PagedArtifactVerification.signHeader(header, with: signer)
            return CoreSnapshot(headerBody: signed.body, headerSignature: signed.signature, pages: pages, cut: cut)
        } catch {
            throw .signingFailed(String(describing: error))
        }
    }
}
