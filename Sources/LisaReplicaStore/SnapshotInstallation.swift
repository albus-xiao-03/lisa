// The full snapshot's staged installation (plan §8.6.3, finding 6): first installation or a new epoch. Staging records
// G0 and the cut, writes each verified chunk into staged tables inside the live database in its own short transaction,
// and builds the staged index from the staged canonical tables plus the journal. Catch-up passes apply local changes
// after the last applied generation, at most 512 per pass, until at most 64 remain or five passes have run. At the
// installation point, one write transaction evaluates the backlog first and invalidates without applying anything if
// it exceeds 2,048 changes, a canonical page beyond the cut was installed after G0, or the epoch or coverage changed;
// otherwise it applies the backlog and swaps the staged canonical tables and index over the live ones together, with
// the cursors at the cut. The journal, drafts and receipts are untouched; a crash before the swap leaves the old view,
// after it the new one, because everything is in one database file.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

extension ReplicaStore {
    public static let catchUpPassChanges = 512
    public static let catchUpTarget = 64
    public static let catchUpPassLimit = 5
    public static let installationBacklogLimit = 2_048
    static let indexBuildStep = 256

    struct InstallationState {
        let installationID: Identifier128
        let epochID: Identifier128
        let cut: Int64
        let pageCount: Int64
        let merkleRoot: Digest256
        let partitions: [String]?
        let startGeneration: Int64
        let appliedGeneration: Int64
    }

    /// Starts staging a full snapshot from its Core-signed paged-artifact header (type `snapshot`, version = the cut).
    /// Any earlier staging is discarded.
    @discardableResult
    public func beginSnapshotInstallation(headerBody: [UInt8], headerSignature: [UInt8], coreKey: P256Verifier)
        throws(ReplicaStoreError) -> PagedArtifactHeader
    {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        guard DomainSignatures.isValid(headerSignature, over: headerBody, domain: .pagedArtifactHeader, by: coreKey)
        else { throw .unverifiedPage(.invalidSignature) }
        let header: PagedArtifactHeader
        do {
            header = try PagedArtifactHeader.decode(body: headerBody)
        } catch {
            throw .unverifiedPage(.malformed(error))
        }
        guard header.artifactType == SnapshotChunk.artifactType, header.datasetID == dataset else {
            throw .unverifiedPage(.wrongDataset)
        }
        let installation = Identifier128.random()
        try write { session in
            try Self.discardStaging(in: session)
            try Self.createStaged(installation, in: session)
            let generation = try LocalChangeJournal.generation(in: session)
            try session.query(
                """
                INSERT INTO installation_state (singleton, installation_id, header_body, epoch_id, cut, page_count,
                  merkle_root, start_generation, applied_generation)
                VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    ReplicaColumns.id(installation), ReplicaColumns.bytes(headerBody),
                    ReplicaColumns.id(header.epochID),
                    .integer(header.version), .integer(header.pageCount), ReplicaColumns.digest(header.merkleRoot),
                    .integer(generation), .integer(generation),
                ])
            // Every item the live view holds gets its staged index entries from the staged view.
            try session.execute(
                """
                INSERT OR IGNORE INTO installation_pending SELECT entity_type, entity_id FROM canonical_operations;
                INSERT OR IGNORE INTO installation_pending SELECT entity_type, entity_id FROM operations;
                INSERT OR IGNORE INTO installation_pending SELECT entity_type, entity_id FROM drafts WHERE state = 'held';
                """)
        }
        return header
    }

    /// Verifies one chunk against the signed root at its index, and every operation in it by the roster, and writes
    /// it into the staged tables in its own transaction. Chunks come from the network or files, never through a long
    /// database reader.
    public func stageSnapshotChunk(
        _ page: PagedArtifactPage, coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        guard let state = try read({ session in try Self.installationState(in: session) }) else {
            throw .noInstallation
        }
        guard page.index < state.pageCount,
            MerkleTree.verifyInclusion(
                page: page.bytes, index: page.index, treeSize: state.pageCount, proof: page.proof,
                root: state.merkleRoot)
        else { throw .snapshotChunkNotIncluded(page.index) }
        let chunk: SnapshotChunk
        do {
            chunk = try SnapshotChunk.decode(body: page.bytes)
        } catch {
            throw .unverifiedPage(.malformed(error))
        }
        guard chunk.entries.allSatisfy({ $0.position <= state.cut }) else {
            throw .unverifiedPage(.malformed(.invalidField("chunk.position")))
        }
        var envelopes: [OperationEnvelope] = []
        var operations: [(signed: SignedOperation, decision: ChangeEntry.Decision)] = []
        var records: [(record: DerivedRecord, position: Int64, partitions: [String])] = []
        var operationEntries: [ChangeEntry] = []
        for entry in chunk.entries {
            // A derived record is vouched for by the signed snapshot; it stages into the staged derived tables.
            if let record = entry.record {
                records.append((record, entry.position, entry.partitions.filter(chunk.partitions.contains)))
                continue
            }
            guard let operation = entry.operation, let decision = entry.decision else {
                throw .unverifiedPage(.malformed(.invalidField("chunk.entry")))
            }
            operationEntries.append(entry)
            do {
                envelopes.append(
                    try OperationSigning.verify(operation, dataset: dataset, deviceKey: deviceKey, coreKey: coreKey))
            } catch {
                throw .unverified(error)
            }
            operations.append((operation, decision))
        }
        try requireRoomBeyondReserve(estimate: 2 * page.bytes.count)
        try write { session in
            let names = chunk.partitions.joined(separator: "\n")
            if let current = state.partitions {
                guard current == chunk.partitions else {
                    throw ReplicaStoreError.unverifiedPage(.malformed(.invalidField("chunk.partitions")))
                }
            } else {
                try session.query("UPDATE installation_state SET partitions = ? WHERE singleton = 1", [.text(names)])
            }
            for (record, position, partitions) in records {
                try Self.stageRecord(record, at: position, through: partitions, in: session)
            }
            for ((entry, envelope), operation) in zip(zip(operationEntries, envelopes), operations) {
                try session.query(
                    """
                    INSERT OR IGNORE INTO staged_canonical_operations
                      (operation_id, entity_type, entity_id, body, signature, epoch_id, position, decision)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        ReplicaColumns.id(envelope.operationID), .text(envelope.entityType),
                        ReplicaColumns.id(envelope.entityID), ReplicaColumns.bytes(operation.signed.body),
                        ReplicaColumns.bytes(operation.signed.signature), ReplicaColumns.id(state.epochID),
                        .integer(entry.position), .text(operation.decision.rawValue),
                    ])
                try session.query(
                    """
                    INSERT INTO staged_canonical_rows (entity_type, entity_id, version) VALUES (?, ?, ?)
                    ON CONFLICT (entity_type, entity_id) DO UPDATE SET version = excluded.version
                    WHERE excluded.version > staged_canonical_rows.version
                    """, [.text(envelope.entityType), ReplicaColumns.id(envelope.entityID), .integer(entry.position)])
                try session.query(
                    "INSERT OR IGNORE INTO installation_pending (entity_type, entity_id) VALUES (?, ?)",
                    [.text(envelope.entityType), ReplicaColumns.id(envelope.entityID)])
            }
            try session.query(
                "INSERT OR IGNORE INTO installation_chunks (chunk_index) VALUES (?)", [.integer(page.index)])
        }
    }

    /// Builds the staged index entries of at most 256 pending items from the staged view; returns how many remain.
    @discardableResult
    public func buildStagedIndexStep() throws(ReplicaStoreError) -> Int {
        try requireRoomBeyondReserve(estimate: 1 << 20)
        return try write { session in
            let rows = try session.query(
                "SELECT entity_type, entity_id FROM installation_pending ORDER BY entity_type, entity_id LIMIT ?",
                [.integer(Int64(Self.indexBuildStep))])
            for row in rows {
                try self.stageIndex(
                    ReplicaItemKey(
                        entityType: try ReplicaColumns.text(row[0]), entityID: try ReplicaColumns.identifier(row[1])),
                    in: session)
            }
            return Int(try session.query("SELECT count(*) FROM installation_pending").first?.first?.integer ?? 0)
        }
    }

    /// The local changes not yet reflected in the staged view and index.
    public func installationBacklog() throws(ReplicaStoreError) -> Int {
        try read { session in
            guard let state = try Self.installationState(in: session) else { throw ReplicaStoreError.noInstallation }
            return Int(
                try session.query(
                    "SELECT count(*) FROM local_changes WHERE generation > ?", [.integer(state.appliedGeneration)]
                )
                .first?.first?.integer ?? 0)
        }
    }

    /// One catch-up pass: at most 512 local changes after the last applied generation, applied to the staged index in
    /// one short transaction. Returns the changes applied.
    @discardableResult
    public func catchUpPass() throws(ReplicaStoreError) -> Int {
        try requireRoomBeyondReserve(estimate: 1 << 20)
        return try write { session in
            guard let state = try Self.installationState(in: session) else { throw ReplicaStoreError.noInstallation }
            let changes = try LocalChangeJournal.changes(
                after: state.appliedGeneration, limit: Self.catchUpPassChanges, in: session)
            try self.stage(changes, in: session)
            if let last = changes.last {
                try session.query(
                    "UPDATE installation_state SET applied_generation = ?, passes = passes + 1 WHERE singleton = 1",
                    [.integer(last.generation)])
            }
            return changes.count
        }
    }

    /// Runs catch-up passes until at most 64 changes remain or five passes have run; returns the passes run.
    @discardableResult
    public func runCatchUpPasses() throws(ReplicaStoreError) -> Int {
        var passes = 0
        while passes < Self.catchUpPassLimit, try installationBacklog() > Self.catchUpTarget {
            try catchUpPass()
            passes += 1
        }
        return passes
    }

    /// The installation point: one write transaction that evaluates the backlog before applying anything, then either
    /// invalidates the staging or applies the backlog and swaps. A truncating checkpoint follows a swap (§8.15.2).
    public func installSnapshot() throws(ReplicaStoreError) -> SnapshotInstallationOutcome {
        try requireRoomBeyondReserve(estimate: 1 << 20)
        let outcome = try write { session -> SnapshotInstallationOutcome in
            guard let state = try Self.installationState(in: session) else { throw ReplicaStoreError.noInstallation }
            let staged = try session.query("SELECT count(*) FROM installation_chunks").first?.first?.integer ?? 0
            guard staged == state.pageCount, let partitions = state.partitions else {
                return .incomplete(missingChunks: Int(state.pageCount - staged))
            }
            let backlog =
                try session.query(
                    "SELECT count(*) FROM local_changes WHERE generation > ?", [.integer(state.appliedGeneration)]
                ).first?.first?.integer ?? 0
            if let reason = try Self.invalidation(
                state: state, partitions: partitions, backlog: Int(backlog), in: session)
            {
                try Self.discardStaging(in: session)
                return .invalidated(reason)
            }
            let changes = try LocalChangeJournal.changes(
                after: state.appliedGeneration, limit: Self.installationBacklogLimit, in: session)
            try self.stage(changes, in: session)
            let pending = try session.query("SELECT entity_type, entity_id FROM installation_pending")
            for row in pending {
                try self.stageIndex(
                    ReplicaItemKey(
                        entityType: try ReplicaColumns.text(row[0]), entityID: try ReplicaColumns.identifier(row[1])),
                    in: session)
            }
            try session.execute(
                """
                DROP TABLE canonical_operations;
                ALTER TABLE staged_canonical_operations RENAME TO canonical_operations;
                DROP TABLE canonical_rows;
                ALTER TABLE staged_canonical_rows RENAME TO canonical_rows;
                DROP TABLE search_postings;
                ALTER TABLE staged_search_postings RENAME TO search_postings;
                DROP TABLE derived_rows;
                ALTER TABLE staged_derived_rows RENAME TO derived_rows;
                DROP TABLE memberships;
                ALTER TABLE staged_memberships RENAME TO memberships;
                DELETE FROM repairs;
                DELETE FROM repair_chunks;
                """)
            // Every covered partition reads the snapshot's membership records (generation 0) from the first reader on.
            for partition in partitions {
                try CanonicalTables.setCursor(
                    partition, epoch: state.epochID, position: state.cut, repairing: false, in: session)
                try session.query(
                    "UPDATE partition_cursors SET published_generation = 0 WHERE partition = ?", [.text(partition)])
            }
            try session.execute(
                """
                UPDATE operations SET overlay = 0, state = c.decision, commit_epoch = c.epoch_id,
                  commit_position = c.position
                FROM canonical_operations c
                WHERE c.operation_id = operations.operation_id AND operations.state != 'rejected';
                DELETE FROM follow_up WHERE kind = 'submit'
                  AND reference IN (SELECT operation_id FROM canonical_operations);
                """)
            // Dependents waiting for an operation that is now canonical are released by its marker.
            for row in try session.query(
                """
                SELECT DISTINCT e.dependency_id FROM causal_edges e
                JOIN canonical_operations c ON c.operation_id = e.dependency_id
                WHERE NOT EXISTS (SELECT 1 FROM causal_decisions d WHERE d.operation_id = e.dependency_id)
                """)
            {
                try CausalReleaseTables.decide(try ReplicaColumns.identifier(row[0]), .applied, in: session)
            }
            try session.execute("DELETE FROM installation_state; DELETE FROM installation_chunks;")
            return .installed(
                generation: try LocalChangeJournal.append(.canonicalPage, operations: [], items: [], in: session))
        }
        if case .installed = outcome { _ = try? database.checkpoint(.truncate) }
        return outcome
    }

    // MARK: - Internals

    /// Stages one derived record of a full snapshot: its row at generation 0 above any staged version, and a
    /// membership record for each covered bucket it belongs to (§8.6.3: the swap installs every partition's membership
    /// records at the cut).
    static func stageRecord(
        _ record: DerivedRecord, at position: Int64, through partitions: [String], in session: SQLiteSession
    )
        throws
    {
        let occurrence = record.occurrence
        let proof = record.zoneProof
        let range = occurrence?.buckets ?? proof?.buckets
        let body: SQLiteValue =
            try record.row.map {
                .blob(Data(try CanonicalEncoder.encode($0, limits: CanonicalLimits(maxBytes: 1 << 16))))
            }
            ?? .null
        try session.query(
            """
            INSERT INTO staged_derived_rows (record_type, record_id, generation, version, body, first_bucket, last_bucket,
              source_id, zone, zone_dependent)
            VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (record_type, record_id, generation) DO UPDATE SET version = excluded.version,
              body = excluded.body, first_bucket = excluded.first_bucket, last_bucket = excluded.last_bucket,
              source_id = excluded.source_id, zone = excluded.zone, zone_dependent = excluded.zone_dependent
            WHERE excluded.version > staged_derived_rows.version
            """,
            [
                .text(record.type), ReplicaColumns.id(record.id), .integer(position), body,
                ReplicaColumns.optionalInteger(range?.lowerBound), ReplicaColumns.optionalInteger(range?.upperBound),
                ReplicaColumns.optionalText(occurrence?.sourceID ?? proof?.sourceID),
                ReplicaColumns.optionalText(occurrence?.expandedZone ?? proof?.zone),
                .integer(occurrence?.movesWithZone == true ? 1 : 0),
            ])
        for partition in partitions {
            guard let bucket = CalendarBuckets.bucket(ofPartition: partition), range?.contains(bucket) == true else {
                continue
            }
            try session.query(
                """
                INSERT INTO staged_memberships (partition, generation, entity_type, entity_id, version) VALUES (?, 0, ?, ?, ?)
                ON CONFLICT (partition, generation, entity_type, entity_id) DO UPDATE SET version = excluded.version
                WHERE excluded.version > staged_memberships.version
                """, [.text(partition), .text(record.type), ReplicaColumns.id(record.id), .integer(position)])
        }
    }

    /// The backlog rule and the never-backward rule, evaluated before anything is applied.
    static func invalidation(state: InstallationState, partitions: [String], backlog: Int, in session: SQLiteSession)
        throws -> SnapshotInstallationOutcome.Invalidation?
    {
        for row in try session.query("SELECT partition FROM partition_cursors") {
            let name = try ReplicaColumns.text(row[0])
            guard partitions.contains(name) else { return .coverageChanged }
            guard let cursor = try CanonicalTables.cursor(name, in: session) else { continue }
            if cursor.epochID != state.epochID { return .epochChanged }
            if cursor.position > state.cut { return .newerCanonicalPage }
        }
        return backlog > installationBacklogLimit ? .backlogTooLarge(backlog) : nil
    }

    /// Applies local changes to the staged index: every item they name gets its staged entries rebuilt.
    func stage(_ changes: [LocalChange], in session: SQLiteSession) throws {
        var items: Set<ReplicaItemKey> = []
        for change in changes { items.formUnion(change.items) }
        for item in items { try stageIndex(item, in: session) }
    }

    /// Rebuilds one item's staged index entries from the staged view.
    func stageIndex(_ item: ReplicaItemKey, in session: SQLiteSession) throws {
        try session.query(
            "DELETE FROM installation_pending WHERE entity_type = ? AND entity_id = ?",
            [.text(item.entityType), ReplicaColumns.id(item.entityID)])
        guard let indexing else { return }
        let text = try Self.searchableText(of: item, in: session, canonicalTable: "staged_canonical_operations")
        do {
            try indexing.stage(item, searchableText: text, into: "staged_search_postings", in: session)
        } catch let error as SQLiteError {
            throw error
        } catch {
            throw ReplicaStoreError.indexFailed("\(error)")
        }
    }

    static func installationState(in session: SQLiteSession) throws -> InstallationState? {
        guard
            let row = try session.query(
                """
                SELECT installation_id, epoch_id, cut, page_count, merkle_root, partitions, start_generation,
                  applied_generation
                FROM installation_state WHERE singleton = 1
                """
            ).first
        else { return nil }
        return InstallationState(
            installationID: try ReplicaColumns.identifier(row[0]), epochID: try ReplicaColumns.identifier(row[1]),
            cut: try ReplicaColumns.integer(row[2]), pageCount: try ReplicaColumns.integer(row[3]),
            merkleRoot: try ReplicaColumns.digest(row[4]),
            partitions: ReplicaColumns.optionalText(row[5]).map { $0.split(separator: "\n").map(String.init) },
            startGeneration: try ReplicaColumns.integer(row[6]), appliedGeneration: try ReplicaColumns.integer(row[7]))
    }

    static func discardStaging(in session: SQLiteSession) throws {
        try session.execute(
            """
            DROP TABLE IF EXISTS staged_canonical_operations;
            DROP TABLE IF EXISTS staged_canonical_rows;
            DROP TABLE IF EXISTS staged_search_postings;
            DROP TABLE IF EXISTS staged_derived_rows;
            DROP TABLE IF EXISTS staged_memberships;
            DELETE FROM installation_state;
            DELETE FROM installation_chunks;
            DELETE FROM installation_pending;
            """)
    }

    /// The staged tables, with index names unique to this installation, so a later staging never collides with the
    /// indexes the swap carried into the live tables.
    static func createStaged(_ installation: Identifier128, in session: SQLiteSession) throws {
        let suffix = installation.hex
        try session.execute(
            """
            CREATE TABLE staged_canonical_operations (
              operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
              entity_type TEXT NOT NULL,
              entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
              body BLOB NOT NULL,
              signature BLOB NOT NULL CHECK (length(signature) = 64),
              epoch_id BLOB NOT NULL CHECK (length(epoch_id) = 16),
              position INTEGER NOT NULL CHECK (position >= 1),
              decision TEXT NOT NULL CHECK (decision IN ('accepted', 'accepted_with_conflict'))
            ) STRICT;
            CREATE INDEX canonical_operations_by_item_\(suffix) ON staged_canonical_operations (entity_type, entity_id);
            CREATE TABLE staged_canonical_rows (
              entity_type TEXT NOT NULL,
              entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
              version INTEGER NOT NULL CHECK (version >= 1),
              body BLOB,
              PRIMARY KEY (entity_type, entity_id)
            ) STRICT, WITHOUT ROWID;
            CREATE TABLE staged_search_postings (
              token TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
              PRIMARY KEY (token, entity_type, entity_id)
            ) STRICT, WITHOUT ROWID;
            CREATE INDEX search_postings_by_item_\(suffix) ON staged_search_postings (entity_type, entity_id);
            CREATE TABLE staged_derived_rows (
              record_type TEXT NOT NULL,
              record_id BLOB NOT NULL CHECK (length(record_id) = 16),
              generation INTEGER NOT NULL DEFAULT 0 CHECK (generation >= 0),
              version INTEGER NOT NULL CHECK (version >= 1),
              body BLOB,
              first_bucket INTEGER,
              last_bucket INTEGER,
              source_id TEXT,
              zone TEXT,
              zone_dependent INTEGER NOT NULL DEFAULT 0 CHECK (zone_dependent IN (0, 1)),
              PRIMARY KEY (record_type, record_id, generation),
              CHECK ((body IS NULL) = (first_bucket IS NULL) AND (first_bucket IS NULL) = (last_bucket IS NULL))
            ) STRICT, WITHOUT ROWID;
            CREATE INDEX derived_rows_by_range_\(suffix) ON staged_derived_rows (record_type, first_bucket, last_bucket);
            CREATE TABLE staged_memberships (
              partition TEXT NOT NULL,
              generation INTEGER NOT NULL DEFAULT 0 CHECK (generation >= 0),
              entity_type TEXT NOT NULL,
              entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
              version INTEGER NOT NULL CHECK (version >= 1),
              PRIMARY KEY (partition, generation, entity_type, entity_id)
            ) STRICT, WITHOUT ROWID;
            """)
    }
}
