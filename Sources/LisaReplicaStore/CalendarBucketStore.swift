// The replica's calendar buckets (plan §8.4.2, §8.4.3): listing a bucket by the absence rule, publishing a bucket repair
// from its Core-signed snapshot (the bucket's membership records become exactly the snapshot's members at the cut,
// then the pages deferred meanwhile apply), and rolling the window (a bucket no window day needs loses its cursor and
// membership records; a row goes only when no covered bucket overlaps its range; nothing is treated as deleted).

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

extension ReplicaStore {
    /// The paged artifact type of a bucket snapshot.
    public static let bucketSnapshotType = "bucket-snapshot"

    /// The occurrences `bucket` lists, by the absence rule: a row whose range overlaps the bucket, whose version is at
    /// most the bucket's cursor and which the bucket's proof didn't deliver at that version, is absent from it. A
    /// bucket the replica doesn't cover lists nothing.
    public func occurrences(inBucket bucket: Int64) throws(ReplicaStoreError) -> [OccurrenceListing] {
        try read { session in
            let partition = CalendarBuckets.partition(bucket)
            guard let cursor = try CanonicalTables.cursor(partition, in: session) else { return [] }
            let rows = try session.query(
                """
                SELECT r.record_id, r.version, r.body, m.version FROM derived_rows r
                LEFT JOIN memberships m ON m.partition = ? AND m.entity_type = r.record_type AND m.entity_id = r.record_id
                WHERE r.record_type = 'occurrence' AND r.body IS NOT NULL AND r.first_bucket <= ? AND r.last_bucket >= ?
                ORDER BY r.record_id
                """, [.text(partition), .integer(bucket), .integer(bucket)])
            var listings: [OccurrenceListing] = []
            for row in rows {
                let version = try ReplicaColumns.integer(row[1])
                let proved = ReplicaColumns.optionalInteger(row[3]) == version
                guard proved || version > cursor.position else { continue }
                let value = try CanonicalDecoder.decode(
                    ReplicaColumns.bytes(row[2]), limits: CanonicalLimits(maxBytes: 1 << 16))
                listings.append(
                    OccurrenceListing(
                        id: try ReplicaColumns.identifier(row[0]), row: try OccurrenceRow(canonicalValue: value),
                        version: version, asOf: cursor.position, provedHere: proved))
            }
            return listings
        }
    }

    /// Publishes a repair of `partition` from its Core-signed bucket snapshot (paged artifact type `bucket-snapshot`,
    /// version = the cut, every chunk naming only this partition): its membership records become exactly the
    /// snapshot's members, each row applied above its version; the cursor becomes the cut if later; then the pages
    /// deferred meanwhile apply, oldest first, for this partition only.
    @discardableResult
    public func finishRepair(
        _ partition: String, snapshotHeaderBody: [UInt8], snapshotHeaderSignature: [UInt8], pages: [PagedArtifactPage],
        coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) -> [PartitionPageOutcome] {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        guard let current = try partitionCursor(partition), current.isRepairing else {
            throw .corrupt("\(partition) isn't being repaired")
        }
        let assembled: (header: PagedArtifactHeader, pages: [[UInt8]])
        do {
            assembled = try PagedArtifactVerification.assemble(
                headerBody: snapshotHeaderBody, headerSignature: snapshotHeaderSignature, pages: pages,
                coreKey: coreKey, expectedType: Self.bucketSnapshotType, dataset: dataset, epoch: current.epochID)
        } catch {
            throw .unverifiedPage(.invalidSignature)
        }
        var records: [(record: DerivedRecord, position: Int64)] = []
        for bytes in assembled.pages {
            let chunk: SnapshotChunk
            do {
                chunk = try SnapshotChunk.decode(body: bytes)
            } catch {
                throw .unverifiedPage(.malformed(error))
            }
            guard chunk.partitions == [partition] else {
                throw .unverifiedPage(.malformed(.invalidField("chunk.partitions")))
            }
            for entry in chunk.entries {
                guard let record = entry.record, entry.position <= assembled.header.version else {
                    throw .unverifiedPage(.malformed(.invalidField("chunk.entries")))
                }
                records.append((record, entry.position))
            }
        }
        let cut = assembled.header.version
        return try write { session in
            try session.query("DELETE FROM memberships WHERE partition = ?", [.text(partition)])
            for (record, position) in records {
                try DerivedRows.apply(record, at: position, through: [partition], in: session)
            }
            try CanonicalTables.setCursor(
                partition, epoch: current.epochID, position: max(current.position, cut), repairing: false, in: session)
            var outcomes: [PartitionPageOutcome] = []
            for signed in try CanonicalTables.takeDeferred(partition, in: session) {
                let page = try ChangePageSigning.verify(signed, dataset: dataset, coreKey: coreKey)
                var envelopes: [OperationEnvelope?] = []
                for entry in page.entries {
                    envelopes.append(
                        try entry.operation.map {
                            try OperationSigning.verify($0, dataset: dataset, deviceKey: deviceKey, coreKey: coreKey)
                        })
                }
                if let outcome = try self.apply(
                    page, signed: signed, envelopes: envelopes, only: partition, in: session)[
                        partition]
                {
                    outcomes.append(outcome)
                }
            }
            try LocalChangeJournal.append(.coverage, operations: [], items: [], in: session)
            return outcomes
        }
    }

    /// Rolls the window: `buckets` lose their cursors, membership records and deferred pages, and an occurrence row
    /// goes only when no covered bucket overlaps its range. Dropping is cache eviction; nothing is treated as deleted.
    public func dropBuckets(_ buckets: [Int64]) throws(ReplicaStoreError) {
        try write { session in
            for bucket in buckets {
                let partition = CalendarBuckets.partition(bucket)
                try session.query("DELETE FROM partition_cursors WHERE partition = ?", [.text(partition)])
                try session.query("DELETE FROM memberships WHERE partition = ?", [.text(partition)])
                try session.query("DELETE FROM deferred_pages WHERE partition = ?", [.text(partition)])
            }
            let covered = try session.query("SELECT partition FROM partition_cursors").compactMap {
                $0.first?.text.flatMap(CalendarBuckets.bucket(ofPartition:))
            }
            for row in try session.query(
                """
                SELECT record_id, first_bucket, last_bucket FROM derived_rows
                WHERE record_type = 'occurrence' AND first_bucket IS NOT NULL
                """)
            {
                let first = try ReplicaColumns.integer(row[1])
                let last = try ReplicaColumns.integer(row[2])
                guard !covered.contains(where: { (first...last).contains($0) }) else { continue }
                try session.query(
                    "DELETE FROM derived_rows WHERE record_type = 'occurrence' AND record_id = ?", [row[0]])
            }
            try LocalChangeJournal.append(.coverage, operations: [], items: [], in: session)
        }
    }
}
