// The replica database's schema, version 1, kept in `PRAGMA user_version` (plan §8.6.1, §8.6.3, §8.4.2, §8.2.2). Every
// table is STRICT. Identifiers are 16-byte blobs, digests 32-byte blobs; canonical JSON is kept as its exact bytes.

import LisaSQLite

/// Creates and checks the replica schema.
enum ReplicaSchema {
    static let version = 1

    /// Creates version 1 on an empty database; accepts version 1; refuses a newer one. Runs inside the caller's write
    /// transaction.
    static func migrate(_ session: SQLiteSession) throws {
        let found = try session.userVersion()
        if found == version { return }
        guard found == 0 else { throw ReplicaStoreError.newerSchema(found) }
        for statement in statements { try session.execute(statement) }
        try session.setUserVersion(version)
    }

    static let statements: [String] = [
        // Who this replica is: the installation, and the dataset and device once enrolled. One row.
        """
        CREATE TABLE replica_identity (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          installation_id BLOB NOT NULL CHECK (length(installation_id) = 16),
          dataset_id BLOB CHECK (dataset_id IS NULL OR length(dataset_id) = 16),
          device_id BLOB CHECK (device_id IS NULL OR length(device_id) = 16),
          created_at INTEGER NOT NULL,
          local_generation INTEGER NOT NULL DEFAULT 0 CHECK (local_generation >= 0)
        ) STRICT
        """,
        // One row per launch that opened the replica (§8.1.1); the link is fixed by the incarnation's first operation.
        """
        CREATE TABLE incarnations (
          ordinal INTEGER PRIMARY KEY,
          incarnation_id BLOB NOT NULL UNIQUE CHECK (length(incarnation_id) = 16),
          started_at INTEGER NOT NULL,
          last_sequence INTEGER NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
          previous_incarnation_id BLOB CHECK (previous_incarnation_id IS NULL OR length(previous_incarnation_id) = 16),
          previous_last_sequence INTEGER CHECK (previous_last_sequence IS NULL OR previous_last_sequence >= 1),
          CHECK ((previous_incarnation_id IS NULL) = (previous_last_sequence IS NULL))
        ) STRICT
        """,
        // The journal of local and relayed operations: exact signed bytes, digest, origin, state, receipt (§8.6.1).
        """
        CREATE TABLE operations (
          operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
          digest BLOB NOT NULL CHECK (length(digest) = 32),
          body BLOB NOT NULL,
          signature BLOB NOT NULL CHECK (length(signature) = 64),
          origin_device BLOB CHECK (origin_device IS NULL OR length(origin_device) = 16),
          origin_incarnation BLOB CHECK (origin_incarnation IS NULL OR length(origin_incarnation) = 16),
          origin_sequence INTEGER CHECK (origin_sequence IS NULL OR origin_sequence >= 1),
          entity_type TEXT NOT NULL,
          entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
          operation_type TEXT NOT NULL,
          source TEXT NOT NULL CHECK (source IN ('local', 'relayed')),
          state TEXT NOT NULL CHECK (state IN ('pending', 'submitted', 'waiting_for_dependencies', 'accepted',
            'accepted_with_conflict', 'rejected')),
          overlay INTEGER NOT NULL CHECK (overlay IN (0, 1)),
          receipt BLOB,
          commit_epoch BLOB CHECK (commit_epoch IS NULL OR length(commit_epoch) = 16),
          commit_position INTEGER CHECK (commit_position IS NULL OR commit_position >= 1),
          stored_generation INTEGER NOT NULL,
          from_draft INTEGER NOT NULL DEFAULT 0 CHECK (from_draft IN (0, 1)),
          UNIQUE (origin_device, origin_incarnation, origin_sequence),
          CHECK ((origin_device IS NULL) = (origin_incarnation IS NULL)
            AND (origin_device IS NULL) = (origin_sequence IS NULL)),
          CHECK ((commit_epoch IS NULL) = (commit_position IS NULL))
        ) STRICT
        """,
        "CREATE INDEX operations_overlay_by_item ON operations (entity_type, entity_id) WHERE overlay = 1",
        // identity_reuse and sequence_reuse (§8.2.1), recorded with both digests.
        """
        CREATE TABLE security_events (
          event_id INTEGER PRIMARY KEY,
          kind TEXT NOT NULL CHECK (kind IN ('identity_reuse', 'sequence_reuse')),
          operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
          arriving_digest BLOB NOT NULL CHECK (length(arriving_digest) = 32),
          known_operation_id BLOB NOT NULL CHECK (length(known_operation_id) = 16),
          known_digest BLOB NOT NULL CHECK (length(known_digest) = 32),
          recorded_at INTEGER NOT NULL
        ) STRICT
        """,
        // Unsigned input kept before enrollment or without a signing key (§8.6.2): the command as canonical JSON, under
        // the operation ID it will be signed with (stable for the life of the logical action, §8.2.1). Rowid order is
        // save order, the order drafts are signed in.
        """
        CREATE TABLE drafts (
          operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
          entity_type TEXT NOT NULL,
          entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
          command BLOB NOT NULL,
          original_input TEXT,
          created_at INTEGER NOT NULL,
          reason TEXT NOT NULL CHECK (reason IN ('not_enrolled', 'key_unavailable')),
          state TEXT NOT NULL CHECK (state IN ('held', 'signed', 'discarded'))
        ) STRICT
        """,
        "CREATE INDEX drafts_held_by_item ON drafts (entity_type, entity_id) WHERE state = 'held'",
        // The local change journal (§8.6.3): one row per change, generation strictly increasing.
        """
        CREATE TABLE local_changes (
          generation INTEGER PRIMARY KEY CHECK (generation >= 1),
          kind TEXT NOT NULL CHECK (kind IN ('journal_entry', 'draft_change', 'receipt', 'rejection', 'revocation',
            'canonical_page', 'coverage', 'conflict_resolution')),
          refs BLOB NOT NULL
        ) STRICT
        """,
        // Work a committed change leaves for later (§8.6.1 step 7).
        """
        CREATE TABLE follow_up (
          follow_up_id INTEGER PRIMARY KEY,
          kind TEXT NOT NULL CHECK (kind IN ('submit', 'sign_draft')),
          reference BLOB NOT NULL CHECK (length(reference) = 16),
          created_generation INTEGER NOT NULL,
          UNIQUE (kind, reference)
        ) STRICT
        """,
        // Causal readiness and bounded release (§8.2.2), persisted step by step as LisaMerge's CausalRelease models it.
        """
        CREATE TABLE causal_edges (
          dependency_id BLOB NOT NULL CHECK (length(dependency_id) = 16),
          dependent_id BLOB NOT NULL CHECK (length(dependent_id) = 16),
          PRIMARY KEY (dependency_id, dependent_id)
        ) STRICT, WITHOUT ROWID
        """,
        "CREATE INDEX causal_edges_by_dependent ON causal_edges (dependent_id, dependency_id)",
        """
        CREATE TABLE causal_waiting (
          operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
          origin_key BLOB NOT NULL
        ) STRICT
        """,
        """
        CREATE TABLE causal_markers (
          marker_id INTEGER PRIMARY KEY,
          operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
          cursor BLOB CHECK (cursor IS NULL OR length(cursor) = 16)
        ) STRICT
        """,
        """
        CREATE TABLE causal_ready (
          ready_id INTEGER PRIMARY KEY,
          operation_id BLOB NOT NULL UNIQUE CHECK (length(operation_id) = 16),
          origin_key BLOB NOT NULL
        ) STRICT
        """,
        """
        CREATE TABLE causal_decisions (
          operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
          decision TEXT NOT NULL CHECK (decision IN ('applied', 'rejected'))
        ) STRICT
        """,
        // Canonical rows and tombstones (body NULL), each with the commit position of the last change it reflects.
        """
        CREATE TABLE canonical_rows (
          entity_type TEXT NOT NULL,
          entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
          version INTEGER NOT NULL CHECK (version >= 1),
          body BLOB,
          PRIMARY KEY (entity_type, entity_id)
        ) STRICT, WITHOUT ROWID
        """,
        // Bounded pieces with their authority, commit position and observed set (§8.3.2).
        """
        CREATE TABLE pieces (
          piece_id BLOB PRIMARY KEY CHECK (length(piece_id) = 16),
          entity_type TEXT NOT NULL,
          entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
          field TEXT NOT NULL,
          operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
          authority TEXT NOT NULL CHECK (authority IN ('owner', 'model', 'source', 'ambiguous')),
          value BLOB NOT NULL,
          observed BLOB,
          commit_epoch BLOB CHECK (commit_epoch IS NULL OR length(commit_epoch) = 16),
          commit_partition TEXT,
          commit_position INTEGER,
          CHECK ((commit_epoch IS NULL) = (commit_position IS NULL)
            AND (commit_epoch IS NULL) = (commit_partition IS NULL))
        ) STRICT
        """,
        "CREATE INDEX pieces_by_field ON pieces (entity_type, entity_id, field)",
        // Partition cursors and repairs, membership records and deferred pages (§8.4.2, §8.4.3).
        """
        CREATE TABLE partition_cursors (
          partition TEXT PRIMARY KEY,
          epoch_id BLOB NOT NULL CHECK (length(epoch_id) = 16),
          cursor INTEGER NOT NULL CHECK (cursor >= 0),
          repairing INTEGER NOT NULL DEFAULT 0 CHECK (repairing IN (0, 1))
        ) STRICT
        """,
        """
        CREATE TABLE memberships (
          partition TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
          version INTEGER NOT NULL CHECK (version >= 1),
          PRIMARY KEY (partition, entity_type, entity_id)
        ) STRICT, WITHOUT ROWID
        """,
        """
        CREATE TABLE deferred_pages (
          page_id INTEGER PRIMARY KEY,
          partition TEXT NOT NULL,
          from_position INTEGER NOT NULL CHECK (from_position >= 0),
          to_position INTEGER NOT NULL,
          page BLOB NOT NULL,
          CHECK (to_position > from_position)
        ) STRICT
        """,
        // Peer custody (§8.6.1): a peer's signed acknowledgement that it durably holds these exact bytes.
        """
        CREATE TABLE custody_acknowledgements (
          operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
          peer_device BLOB NOT NULL CHECK (length(peer_device) = 16),
          digest BLOB NOT NULL CHECK (length(digest) = 32),
          acknowledged_at INTEGER NOT NULL,
          signature BLOB NOT NULL CHECK (length(signature) = 64),
          PRIMARY KEY (operation_id, peer_device)
        ) STRICT, WITHOUT ROWID
        """,
    ]
}
