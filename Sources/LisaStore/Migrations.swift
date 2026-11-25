// The versioned schema: explicit, append-only migrations. Never edit a released migration; add a new one.

import Foundation

/// One schema migration, applied in its own transaction together with the `user_version` update.
public struct Migration: Hashable, Sendable {
    public let version: Int
    public let summary: String
    public let statements: [String]

    public init(version: Int, summary: String, statements: [String]) {
        self.version = version
        self.summary = summary
        self.statements = statements
    }
}

/// Lisa's migrations, oldest first.
public enum Migrations {
    public static let all: [Migration] = [version1, version2, version3, version4, version5]

    /// The newest schema version this build understands.
    public static var latestVersion: Int { all.map(\.version).max() ?? 0 }

    /// Statements creating a record table with indexed columns.
    static func table(_ name: String, _ columns: [(String, String, Bool)]) -> [String] {
        let extra = columns.map { ", \($0.0) \($0.1)" }.joined()
        var statements = [
            "CREATE TABLE \(name) (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, updated_at INTEGER NOT NULL, body TEXT NOT NULL\(extra))"
        ]
        for (column, _, unique) in columns {
            statements.append("CREATE \(unique ? "UNIQUE " : "")INDEX \(name)_\(column) ON \(name)(\(column))")
        }
        statements.append("CREATE INDEX \(name)_updated_at ON \(name)(updated_at)")
        return statements
    }

    static let version1 = Migration(
        version: 1, summary: "core collections",
        statements:
            table(
                "sources",
                [("kind", "TEXT", false), ("configuration_key", "TEXT", true), ("enabled", "INTEGER", false)])
            + table(
                "evidence", [("source_id", "TEXT", false), ("external_id", "TEXT", false), ("kind", "TEXT", false)])
            + table(
                "emails",
                [
                    ("source_id", "TEXT", false), ("dedup_key", "TEXT", true), ("message_id", "TEXT", false),
                    ("received_at", "INTEGER", false), ("extraction", "TEXT", false),
                ])
            + table(
                "occurrences",
                [
                    ("source_id", "TEXT", false), ("natural_key", "TEXT", true), ("uid", "TEXT", false),
                    ("start_at", "INTEGER", false), ("end_at", "INTEGER", false), ("status", "TEXT", false),
                ])
            + table(
                "tasks",
                [
                    ("status", "TEXT", false), ("confirmation", "TEXT", false), ("deadline_at", "INTEGER", false),
                    ("origin", "TEXT", false),
                ])
            + table("proposals", [("match_state", "TEXT", false), ("created_at", "INTEGER", false)])
            + table("ideas", [("lifecycle", "TEXT", false), ("created_at", "INTEGER", false)])
            + table(
                "captures",
                [("request_id", "TEXT", true), ("captured_at", "INTEGER", false), ("processing", "TEXT", false)])
            + table("preferences", [("key", "TEXT", true)])
            + table(
                "news",
                [
                    ("source_id", "TEXT", false), ("dedup_key", "TEXT", true), ("published_at", "INTEGER", false),
                    ("retrieved_at", "INTEGER", false),
                ])
            + table("plans", [("natural_key", "TEXT", true), ("local_date", "TEXT", false)])
            + table("briefs", [("natural_key", "TEXT", true), ("local_date", "TEXT", false), ("state", "TEXT", false)])
            + table(
                "reminders",
                [
                    ("occurrence_key", "TEXT", true), ("state", "TEXT", false), ("due_at", "INTEGER", false),
                    ("subject_key", "TEXT", false), ("rule", "TEXT", false),
                ])
            + table(
                "deliveries",
                [
                    ("idempotency_key", "TEXT", true), ("state", "TEXT", false), ("next_attempt_at", "INTEGER", false),
                    ("lease_expires_at", "INTEGER", false), ("channel", "TEXT", false),
                    ("recipient_key", "TEXT", false),
                ])
            + table("audit", [("at", "INTEGER", false), ("action", "TEXT", false)])
            + [
                "CREATE TABLE raw_content (id TEXT PRIMARY KEY, kind TEXT NOT NULL, stored_at INTEGER NOT NULL, size INTEGER NOT NULL, data BLOB NOT NULL)",
                "CREATE INDEX raw_content_stored_at ON raw_content(stored_at)",
            ])

    static let version2 = Migration(
        version: 2, summary: "paired devices and notification occurrences",
        statements:
            table(
                "devices",
                [("installation_id", "TEXT", true), ("credential_verifier", "TEXT", true), ("state", "TEXT", false)])
            + table(
                "notifications",
                [
                    ("occurrence_key", "TEXT", true), ("subject_key", "TEXT", false), ("category", "TEXT", false),
                    ("state", "TEXT", false), ("created_at", "INTEGER", false),
                ]))

    static let version3 = Migration(
        version: 3, summary: "API idempotency records; delivery payload keys backfilled from stored records",
        statements:
            table("idempotency", [("scoped_key", "TEXT", true), ("expires_at", "INTEGER", false)]) + [
                "ALTER TABLE deliveries ADD COLUMN payload_key TEXT",
                """
                UPDATE deliveries SET payload_key = COALESCE(
                    'reminder:' || json_extract(body, '$.payload.reminder._0'),
                    'brief:' || json_extract(body, '$.payload.brief._0'),
                    'notification:' || json_extract(body, '$.payload.notification._0'))
                """,
                "CREATE INDEX deliveries_payload_key ON deliveries(payload_key)",
            ])

    /// A request ID identifies a capture only together with its caller (D-35), so two devices may use the same ID.
    /// The unique `request_id` column now holds `Capture.requestKey`, `<principal>:<request ID>`, derived here from
    /// each stored record exactly as `Principal.description` spells the caller.
    static let version4 = Migration(
        version: 4, summary: "capture request keys name the caller as well as the request ID",
        statements: [
            """
            UPDATE captures SET request_id = (CASE
                WHEN json_type(body, '$.principal.pairedDevice') IS NOT NULL
                    THEN 'device:' || json_extract(body, '$.principal.pairedDevice._0')
                WHEN json_type(body, '$.principal.localOwner') IS NOT NULL THEN 'local-owner'
                WHEN json_type(body, '$.principal.runtime') IS NOT NULL THEN 'runtime'
                WHEN json_type(body, '$.principal.model') IS NOT NULL THEN 'model'
                WHEN json_type(body, '$.principal.demonstration') IS NOT NULL THEN 'demonstration'
                END) || ':' || json_extract(body, '$.requestID')
            WHERE json_extract(body, '$.requestID') IS NOT NULL
            """
        ])

    /// The R2 Core ledger (plan §8.4.1): the dataset, epoch and recovery state; the operations with their decisions,
    /// receipts and commit positions, unique by origin triple; dependencies, release markers and the ready queue; the
    /// change log with each entry's partitions; tombstones; and the duplicate rules' security events. R1's
    /// collections are untouched: intake projects each entity into them in the same transaction. Every table keeps its
    /// rowid, as R1's maintenance and its tests read tables in rowid order.
    static let version5 = Migration(
        version: 5, summary: "R2 Core ledger: operations, receipts, causal release, change log, tombstones",
        statements: [
            """
            CREATE TABLE core_dataset (
              singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
              dataset_id BLOB NOT NULL CHECK (length(dataset_id) = 16),
              epoch_id BLOB NOT NULL CHECK (length(epoch_id) = 16),
              recovery_state TEXT NOT NULL CHECK (recovery_state IN ('normal')),
              last_position INTEGER NOT NULL CHECK (last_position >= 0),
              created_at INTEGER NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE core_operations (
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
              state TEXT NOT NULL CHECK (state IN ('waiting', 'accepted', 'accepted_with_conflict', 'rejected')),
              reason TEXT,
              position INTEGER UNIQUE CHECK (position IS NULL OR position >= 1),
              epoch_id BLOB NOT NULL CHECK (length(epoch_id) = 16),
              received_at INTEGER NOT NULL,
              receipt BLOB,
              UNIQUE (origin_device, origin_incarnation, origin_sequence),
              CHECK ((origin_device IS NULL) = (origin_incarnation IS NULL)
                AND (origin_device IS NULL) = (origin_sequence IS NULL)),
              CHECK ((state = 'waiting') = (position IS NULL))
            ) STRICT
            """,
            "CREATE INDEX core_operations_by_item ON core_operations (entity_type, entity_id, position)",
            """
            CREATE TABLE core_change_log (
              position INTEGER PRIMARY KEY CHECK (position >= 1),
              operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
              partitions TEXT NOT NULL,
              decision TEXT NOT NULL CHECK (decision IN ('accepted', 'accepted_with_conflict', 'rejected')),
              epoch_id BLOB NOT NULL CHECK (length(epoch_id) = 16)
            ) STRICT
            """,
            """
            CREATE TABLE core_causal_edges (
              dependency_id BLOB NOT NULL CHECK (length(dependency_id) = 16),
              dependent_id BLOB NOT NULL CHECK (length(dependent_id) = 16),
              PRIMARY KEY (dependency_id, dependent_id)
            ) STRICT
            """,
            "CREATE INDEX core_causal_edges_by_dependent ON core_causal_edges (dependent_id, dependency_id)",
            """
            CREATE TABLE core_causal_waiting (
              operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
              origin_key BLOB NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE core_causal_markers (
              marker_id INTEGER PRIMARY KEY,
              operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
              cursor BLOB CHECK (cursor IS NULL OR length(cursor) = 16)
            ) STRICT
            """,
            """
            CREATE TABLE core_causal_ready (
              ready_id INTEGER PRIMARY KEY,
              operation_id BLOB NOT NULL UNIQUE CHECK (length(operation_id) = 16),
              origin_key BLOB NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE core_causal_decisions (
              operation_id BLOB PRIMARY KEY CHECK (length(operation_id) = 16),
              decision TEXT NOT NULL CHECK (decision IN ('applied', 'rejected'))
            ) STRICT
            """,
            """
            CREATE TABLE core_tombstones (
              entity_type TEXT NOT NULL,
              entity_id BLOB NOT NULL CHECK (length(entity_id) = 16),
              position INTEGER NOT NULL CHECK (position >= 1),
              PRIMARY KEY (entity_type, entity_id)
            ) STRICT
            """,
            """
            CREATE TABLE core_security_events (
              event_id INTEGER PRIMARY KEY,
              kind TEXT NOT NULL CHECK (kind IN ('identity_reuse', 'sequence_reuse')),
              operation_id BLOB NOT NULL CHECK (length(operation_id) = 16),
              arriving_digest BLOB NOT NULL CHECK (length(arriving_digest) = 32),
              known_operation_id BLOB NOT NULL CHECK (length(known_operation_id) = 16),
              known_digest BLOB NOT NULL CHECK (length(known_digest) = 32),
              recorded_at INTEGER NOT NULL
            ) STRICT
            """,
        ])
}
