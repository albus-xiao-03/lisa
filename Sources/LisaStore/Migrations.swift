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
    public static let all: [Migration] = [version1, version2, version3, version4]

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
}
