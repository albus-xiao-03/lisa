// The replica's calendar buckets (plan §8.4.2, §8.4.3): listing a bucket by the absence rule, repairing a bucket from its
// Core-signed snapshot, and rolling the window.
//
// A repair, step by step (§8.4.3):
// 1. **Record:** the snapshot, its cut, the epoch and the cursor at the start; a cut older than the cursor is refused.
// 2. **Serialize:** the bucket is repairing; pages listing it are deferred for it and its cursor doesn't move.
// 3. **Stage, invisibly:** each chunk of at most 512 rows goes into the repair's own generation in its own transaction.
//    The overlay watermark advances with every local change.
// 4. **Publish, in one transaction of constant size:** re-check the epoch, the cursor and the watermark, then flip the
//    bucket's published generation and set its cursor; readers resolve rows to their newest published version and the
//    bucket's membership to its published generation, so they see one view or the other, never a mixture.
// 5. **Apply the deferred pages** in order, each in its own transaction.
// 6. **Clean up** superseded generations in bounded chunks that readers never see.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

extension ReplicaStore {
    /// The paged artifact type of a bucket snapshot.
    public static let bucketSnapshotType = "bucket-snapshot"
    /// The most rows one repair chunk may stage.
    public static let repairChunkRows = 512

    /// The occurrences `bucket` lists, by the absence rule: a row whose range overlaps the bucket, whose newest
    /// published version is at most the bucket's cursor and which the bucket's published proof didn't deliver at that
    /// version, is absent from it. A bucket the replica doesn't cover lists nothing.
    public func occurrences(inBucket bucket: Int64) throws(ReplicaStoreError) -> [OccurrenceListing] {
        try read { session in
            let partition = CalendarBuckets.partition(bucket)
            guard let cursor = try CanonicalTables.cursor(partition, in: session) else { return [] }
            let generation = try CanonicalTables.publishedGeneration(partition, in: session)
            let rows = try session.query(
                """
                WITH newest AS (
                  SELECT record_type, record_id, max(version) AS version FROM derived_rows
                  WHERE record_type = 'occurrence' AND generation IN \(DerivedRows.published)
                  GROUP BY record_type, record_id)
                SELECT DISTINCT r.record_id, r.version, r.body, m.version FROM newest n
                JOIN derived_rows r ON r.record_type = n.record_type AND r.record_id = n.record_id
                  AND r.version = n.version AND r.generation IN \(DerivedRows.published)
                LEFT JOIN memberships m ON m.partition = ? AND m.generation = ? AND m.entity_type = r.record_type
                  AND m.entity_id = r.record_id
                WHERE r.body IS NOT NULL AND r.first_bucket <= ? AND r.last_bucket >= ?
                ORDER BY r.record_id
                """, [.text(partition), .integer(generation), .integer(bucket), .integer(bucket)])
            var listings: [OccurrenceListing] = []
            var seen: Set<Identifier128> = []
            for row in rows {
                let id = try ReplicaColumns.identifier(row[0])
                guard seen.insert(id).inserted else { continue }
                let version = try ReplicaColumns.integer(row[1])
                let proved = ReplicaColumns.optionalInteger(row[3]) == version
                guard proved || version > cursor.position else { continue }
                let value = try CanonicalDecoder.decode(
                    ReplicaColumns.bytes(row[2]), limits: CanonicalLimits(maxBytes: 1 << 16))
                listings.append(
                    OccurrenceListing(
                        id: id, row: try OccurrenceRow(canonicalValue: value), version: version, asOf: cursor.position,
                        provedHere: proved))
            }
            return listings
        }
    }

    /// Step 1: records a repair of `partition` from its Core-signed bucket snapshot header (type `bucket-snapshot`,
    /// version = the cut) and marks the bucket repairing. A bucket without a cursor (entering the window) starts at 0.
    @discardableResult
    public func beginBucketRepair(
        _ partition: String, snapshotHeaderBody: [UInt8], snapshotHeaderSignature: [UInt8], coreKey: P256Verifier
    ) throws(ReplicaStoreError) -> Int64 {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        guard
            DomainSignatures.isValid(
                snapshotHeaderSignature, over: snapshotHeaderBody, domain: .pagedArtifactHeader, by: coreKey)
        else { throw .unverifiedPage(.invalidSignature) }
        let header: PagedArtifactHeader
        do {
            header = try PagedArtifactHeader.decode(body: snapshotHeaderBody)
        } catch {
            throw .unverifiedPage(.malformed(error))
        }
        guard header.artifactType == Self.bucketSnapshotType, header.datasetID == dataset else {
            throw .unverifiedPage(.wrongDataset)
        }
        return try write { session in
            let current = try CanonicalTables.cursor(partition, in: session)
            if let current {
                guard current.epochID == header.epochID else {
                    throw ReplicaStoreError.repairAbandoned("another epoch")
                }
                guard header.version >= current.position else { throw ReplicaStoreError.staleSnapshot }
            }
            try Self.abandonRepair(partition, in: session)
            let generation =
                (try session.query(
                    """
                    SELECT max(g) FROM (SELECT max(generation) AS g FROM repairs
                      UNION ALL SELECT max(published_generation) FROM partition_cursors
                      UNION ALL SELECT max(generation) FROM derived_rows
                      UNION ALL SELECT max(generation) FROM memberships)
                    """
                ).first?.first?.integer ?? 0) + 1
            try session.query(
                """
                INSERT INTO repairs (generation, partition, epoch_id, cut, start_cursor, page_count, merkle_root,
                  overlay_watermark)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .integer(generation), .text(partition), ReplicaColumns.id(header.epochID), .integer(header.version),
                    .integer(current?.position ?? 0), .integer(header.pageCount),
                    ReplicaColumns.digest(header.merkleRoot),
                    .integer(try LocalChangeJournal.generation(in: session)),
                ])
            try CanonicalTables.setCursor(
                partition, epoch: header.epochID, position: current?.position ?? 0, repairing: true, in: session)
            return generation
        }
    }

    /// Step 3: verifies one chunk against the repair's signed root and stages its rows, at most 512, in the repair's
    /// generation, invisible to readers.
    public func stageBucketRepairChunk(_ partition: String, _ page: PagedArtifactPage) throws(ReplicaStoreError) {
        try requireRoomBeyondReserve(estimate: 2 * page.bytes.count)
        try write { session in
            guard let repair = try Self.repair(partition, in: session) else { throw ReplicaStoreError.noInstallation }
            guard page.index < repair.pageCount,
                MerkleTree.verifyInclusion(
                    page: page.bytes, index: page.index, treeSize: repair.pageCount, proof: page.proof,
                    root: repair.merkleRoot)
            else { throw ReplicaStoreError.snapshotChunkNotIncluded(page.index) }
            let chunk = try SnapshotChunk.decode(body: page.bytes)
            guard chunk.partitions == [partition], chunk.entries.count <= Self.repairChunkRows else {
                throw ReplicaStoreError.unverifiedPage(.malformed(.invalidField("chunk")))
            }
            for entry in chunk.entries {
                guard let record = entry.record, entry.position <= repair.cut else {
                    throw ReplicaStoreError.unverifiedPage(.malformed(.invalidField("chunk.entries")))
                }
                try DerivedRows.apply(
                    record, at: entry.position, generation: repair.generation,
                    through: [(partition, repair.generation)], in: session)
            }
            try session.query(
                "INSERT OR IGNORE INTO repair_chunks (generation, chunk_index) VALUES (?, ?)",
                [.integer(repair.generation), .integer(page.index)])
        }
    }

    /// Steps 4 and 5: re-checks and publishes in one transaction of constant size, then applies the pages deferred
    /// meanwhile, each in its own transaction. Returns their outcomes for this partition.
    @discardableResult
    public func publishBucketRepair(
        _ partition: String, coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) -> [PartitionPageOutcome] {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        try write { session in
            guard let repair = try Self.repair(partition, in: session),
                let cursor = try CanonicalTables.cursor(partition, in: session)
            else { throw ReplicaStoreError.noInstallation }
            let staged =
                try session.query(
                    "SELECT count(*) FROM repair_chunks WHERE generation = ?", [.integer(repair.generation)]
                ).first?.first?.integer ?? 0
            guard staged == repair.pageCount else {
                throw ReplicaStoreError.repairIncomplete(Int(repair.pageCount - staged))
            }
            guard cursor.epochID == repair.epochID else { throw ReplicaStoreError.repairAbandoned("another epoch") }
            guard cursor.position == repair.startCursor else {
                throw ReplicaStoreError.repairAbandoned("the cursor moved")
            }
            // The watermark equals the local state generation, because every local change advanced it.
            guard repair.overlayWatermark == (try LocalChangeJournal.generation(in: session)) else {
                throw ReplicaStoreError.corrupt("the repair's overlay watermark fell behind")
            }
            try session.query(
                """
                UPDATE partition_cursors SET published_generation = ?, cursor = max(cursor, ?), repairing = 0
                WHERE partition = ?
                """, [.integer(repair.generation), .integer(repair.cut), .text(partition)])
            try session.query("DELETE FROM repairs WHERE generation = ?", [.integer(repair.generation)])
            try session.query("DELETE FROM repair_chunks WHERE generation = ?", [.integer(repair.generation)])
            try LocalChangeJournal.append(.coverage, operations: [], items: [], in: session)
        }
        var outcomes: [PartitionPageOutcome] = []
        while let outcome = try write({ session -> PartitionPageOutcome? in
            guard
                let row = try session.query(
                    """
                    SELECT page_id, page, signature FROM deferred_pages WHERE partition = ?
                    ORDER BY from_position, page_id LIMIT 1
                    """, [.text(partition)]
                ).first
            else { return nil }
            try session.query("DELETE FROM deferred_pages WHERE page_id = ?", [row[0]])
            let signed = try SignedChangePage(
                body: ReplicaColumns.bytes(row[1]), signature: ReplicaColumns.bytes(row[2]))
            let page = try ChangePageSigning.verify(signed, dataset: dataset, coreKey: coreKey)
            var envelopes: [OperationEnvelope?] = []
            for entry in page.entries {
                envelopes.append(
                    try entry.operation.map {
                        try OperationSigning.verify($0, dataset: dataset, deviceKey: deviceKey, coreKey: coreKey)
                    })
            }
            return try self.apply(page, signed: signed, envelopes: envelopes, only: partition, in: session)[partition]
                ?? .ignored(cursor: -1)
        }) {
            outcomes.append(outcome)
        }
        return outcomes
    }

    /// Step 6: removes superseded membership records and rows in bounded chunks; returns how many were removed.
    @discardableResult
    public func cleanUpRepairs(limit: Int = 512) throws(ReplicaStoreError) -> Int {
        try write { session in
            try session.query(
                """
                DELETE FROM memberships WHERE (partition, generation, entity_type, entity_id) IN (
                  SELECT m.partition, m.generation, m.entity_type, m.entity_id FROM memberships m
                  LEFT JOIN partition_cursors c ON c.partition = m.partition
                  WHERE m.generation != coalesce(c.published_generation, -1)
                    AND m.generation NOT IN (SELECT generation FROM repairs)
                  LIMIT ?)
                """, [.integer(Int64(limit))])
            var removed = session.changes
            try session.query(
                """
                DELETE FROM derived_rows WHERE (record_type, record_id, generation) IN (
                  SELECT record_type, record_id, generation FROM derived_rows
                  WHERE generation NOT IN \(DerivedRows.published) AND generation NOT IN (SELECT generation FROM repairs)
                  LIMIT ?)
                """, [.integer(Int64(limit))])
            removed += session.changes
            return removed
        }
    }

    /// The one-call repair publication from a bucket snapshot: record, stage every chunk, publish, then clean up.
    @discardableResult
    public func finishRepair(
        _ partition: String, snapshotHeaderBody: [UInt8], snapshotHeaderSignature: [UInt8], pages: [PagedArtifactPage],
        coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) -> [PartitionPageOutcome] {
        try beginBucketRepair(
            partition, snapshotHeaderBody: snapshotHeaderBody, snapshotHeaderSignature: snapshotHeaderSignature,
            coreKey: coreKey)
        for page in pages { try stageBucketRepairChunk(partition, page) }
        let outcomes = try publishBucketRepair(partition, coreKey: coreKey, deviceKey: deviceKey)
        while try cleanUpRepairs() > 0 {}
        return outcomes
    }

    /// Rolls the window: `buckets` lose their cursors, membership records, deferred pages and repairs, and an
    /// occurrence row goes only when no covered bucket overlaps its range. Dropping is cache eviction; nothing is
    /// treated as deleted.
    public func dropBuckets(_ buckets: [Int64]) throws(ReplicaStoreError) {
        try write { session in
            for bucket in buckets {
                let partition = CalendarBuckets.partition(bucket)
                try Self.abandonRepair(partition, in: session)
                try session.query("DELETE FROM partition_cursors WHERE partition = ?", [.text(partition)])
                try session.query("DELETE FROM memberships WHERE partition = ?", [.text(partition)])
                try session.query("DELETE FROM deferred_pages WHERE partition = ?", [.text(partition)])
            }
            let covered = try session.query("SELECT partition FROM partition_cursors").compactMap {
                $0.first?.text.flatMap(CalendarBuckets.bucket(ofPartition:))
            }
            for row in try session.query(
                """
                SELECT DISTINCT record_id, first_bucket, last_bucket FROM derived_rows
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

    // MARK: - Internals

    struct Repair {
        let generation: Int64
        let epochID: Identifier128
        let cut: Int64
        let startCursor: Int64
        let pageCount: Int64
        let merkleRoot: Digest256
        let overlayWatermark: Int64
    }

    static func repair(_ partition: String, in session: SQLiteSession) throws -> Repair? {
        guard
            let row = try session.query(
                """
                SELECT generation, epoch_id, cut, start_cursor, page_count, merkle_root, overlay_watermark
                FROM repairs WHERE partition = ?
                """, [.text(partition)]
            ).first
        else { return nil }
        return Repair(
            generation: try ReplicaColumns.integer(row[0]), epochID: try ReplicaColumns.identifier(row[1]),
            cut: try ReplicaColumns.integer(row[2]), startCursor: try ReplicaColumns.integer(row[3]),
            pageCount: try ReplicaColumns.integer(row[4]), merkleRoot: try ReplicaColumns.digest(row[5]),
            overlayWatermark: try ReplicaColumns.integer(row[6]))
    }

    /// Abandons an unpublished repair of `partition`: its record goes; its staged rows become garbage for cleanup.
    static func abandonRepair(_ partition: String, in session: SQLiteSession) throws {
        guard let repair = try repair(partition, in: session) else { return }
        try session.query("DELETE FROM repairs WHERE generation = ?", [.integer(repair.generation)])
        try session.query("DELETE FROM repair_chunks WHERE generation = ?", [.integer(repair.generation)])
    }
}
