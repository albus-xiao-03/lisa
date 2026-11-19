// Recovery tests for L23, a failed migration (DATA-02; D-23): a migration that fails part-way, after its first
// statements have already changed the schema and existing records, is reported as a failure and rolled back. Afterwards
// the schema version, every record and the database file are as they were, nothing the failed migration created
// remains, the pre-migration copy holds the same data, and the store opens normally again. A host's data directory
// survives a failed upgrade tried twice: each attempt is reported and keeps its own copy, and the host then opens with
// everything the owner had. Every version number is derived from `Migrations.latestVersion`, so the tests stay valid as
// migrations are added.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaPorts
import LisaSQLite
import LisaStore
import LisaTime
import Testing

@Suite("L23 — Failed migration", .tags(.recovery))
struct L23FailedMigrationTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    /// How the deliberately broken migration stops, after its first statements have succeeded.
    enum Failure: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A new unique index over values the existing records share: a failure caused by the data itself.
        case uniqueIndexOverSharedValues
        /// A statement that names a table that does not exist.
        case missingTable

        var testDescription: String {
            switch self {
            case .uniqueIndexOverSharedValues: "a unique index over values the records share"
            case .missingTable: "a statement naming a missing table"
            }
        }
    }

    /// The prefix of every schema object the broken migration creates.
    private static let probe = "t5_failed_migration"

    /// A test-only migration one version past the newest. Its first statements succeed: a new table and index, rows
    /// copied from the tasks, a new column on the tasks filled from their status, and every idea's original capture
    /// rewritten. Then `failure` stops it.
    private static func brokenMigration(_ failure: Failure) -> Migration {
        let early = [
            "CREATE TABLE \(probe)_table (id TEXT PRIMARY KEY, title TEXT)",
            "CREATE INDEX \(probe)_index ON \(probe)_table(title)",
            "INSERT INTO \(probe)_table (id, title) SELECT id, json_extract(body, '$.title') FROM tasks",
            "ALTER TABLE tasks ADD COLUMN \(probe)_column TEXT",
            "UPDATE tasks SET \(probe)_column = status",
            "UPDATE ideas SET body = json_set(body, '$.originalCapture', 'rewritten by a failed migration')",
        ]
        let last =
            switch failure {
            case .uniqueIndexOverSharedValues: "CREATE UNIQUE INDEX \(probe)_unique ON tasks(\(probe)_column)"
            case .missingTable: "INSERT INTO \(probe)_missing (id) VALUES ('synthetic')"
            }
        return Migration(
            version: Migrations.latestVersion + 1, summary: "a deliberately broken migration (test-only)",
            statements: early + [last])
    }

    /// Everything a database holds, read with SQL: its schema version, every schema object with its definition, and
    /// every row of every table.
    private struct DatabaseContents: Equatable {
        var userVersion: Int
        var schema: [[SQLiteValue]]
        var rows: [String: [[SQLiteValue]]]
        var integrity: String

        /// Reads the database at `path`, which must exist.
        init(path: String) throws {
            let database = try SQLiteDatabase(path: path, create: false)
            let read = try database.readTransaction { session in
                let version = try session.userVersion()
                let schema = try session.query(
                    "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")
                let tables = try session.query("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
                    .compactMap { $0.first?.text }
                var rows: [String: [[SQLiteValue]]] = [:]
                for table in tables {
                    rows[table] = try session.query("SELECT * FROM \"\(table)\" ORDER BY rowid")
                }
                let integrity = try session.query("PRAGMA integrity_check").first?.first?.text ?? ""
                return (version: version, schema: schema, rows: rows, integrity: integrity)
            }
            userVersion = read.version
            schema = read.schema
            rows = read.rows
            integrity = read.integrity
        }

        /// The names of schema objects the broken migration would have created.
        var probeObjects: [String] {
            schema.compactMap { $0.count > 1 ? $0[1].text : nil }.filter { $0.hasPrefix(L23FailedMigrationTests.probe) }
        }

        /// Whether any table definition mentions the broken migration's objects, such as its column on the tasks.
        var mentionsProbe: Bool {
            schema.contains { row in row.contains { $0.text?.contains(L23FailedMigrationTests.probe) == true } }
        }
    }

    /// The identity of the database file: its file number (so a recreated file is noticed) and its permissions.
    private struct FileIdentity: Equatable {
        var fileNumber: UInt64
        var permissions: Int

        init(path: String) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            fileNumber = try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
            permissions = try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
        }
    }

    /// The records written before the failed migration, as stored.
    private struct Written {
        var tasks: [LisaTask]
        var idea: Idea
        var capture: Capture
        var preference: Preference
        var raw: RawContentRef
        var rawBytes: Data
    }

    /// Creates a current database at `path` and writes records into it through the store: two open tasks, an idea with
    /// its capture, a preference changed once (revision 2) and raw content. The store is released before returning, as
    /// when a host stops.
    private func writeRecords(at path: String, now: Date) throws -> Written {
        let storage = try LisaStorage.open(path: path, now: now)
        #expect(storage.migration.toVersion == Migrations.latestVersion)
        let tasks = [
            SyntheticTask.confirmed(
                "Submit the synthetic grant report",
                deadline: SyntheticTask.due(TestTime.instant("2026-11-18T17:00", in: TestTime.newYork)),
                createdAt: now),
            SyntheticTask.confirmed(
                "Renew the synthetic parking permit", priority: .normal, deadline: nil, createdAt: now),
        ]
        let text = "A synthetic idea: a rooftop garden for the office"
        var capture = Capture(
            kind: .idea, text: text, url: nil, channel: .commandLine, principal: .localOwner,
            requestID: "failed-migration-idea-0001", now: now)
        let idea = Idea(originalCapture: text, captureID: capture.id, now: now)
        capture.resultingIdeaID = idea.id
        capture.processing = .processed
        let preference = Preference(key: .bufferMinutes, value: .number(15), origin: .explicit, now: now)
        try storage.records.write { tx in
            for task in tasks { try tx.insert(task) }
            try tx.insert(idea)
            try tx.insert(capture)
            try tx.insert(preference)
        }
        try storage.records.write { tx in
            var stored = try tx.require(Preference.self, id: preference.id)
            stored.value = .number(20)
            try tx.update(stored)
        }
        let rawBytes = Data("Synthetic raw message bytes for owner@example.com".utf8)
        let raw = try storage.rawContent.put(rawBytes, kind: "message", now: now)
        return try storage.records.read { tx in
            Written(
                tasks: try tasks.map { try tx.require(LisaTask.self, id: $0.id) },
                idea: try tx.require(Idea.self, id: idea.id), capture: try tx.require(Capture.self, id: capture.id),
                preference: try tx.require(Preference.self, id: preference.id), raw: raw, rawBytes: rawBytes)
        }
    }

    /// `entity` in the stored JSON form, for comparing a record with what was read before.
    private func json(_ entity: some Entity) throws -> String {
        String(decoding: try DomainJSON.encoder().encode(entity), as: UTF8.self)
    }

    /// The pre-migration copy D-23 documents for an attempt at `attempt` on a database of schema `version`:
    /// `<db>.pre-migration-v<n>-<ms>.sqlite`.
    private func preMigrationCopy(of path: String, version: Int, attempt: Date) -> String {
        "\(path).pre-migration-v\(version)-\(attempt.millisecondsSince1970).sqlite"
    }

    /// Runs the open with the broken migration and returns the version it reports as failed, or records an issue.
    private func failedOpen(_ path: String, at attempt: Date, _ failure: Failure) -> Int? {
        let migrations = Migrations.all + [Self.brokenMigration(failure)]
        let error = #expect(throws: StoreError.self) {
            _ = try LisaStorage.open(path: path, now: attempt, migrations: migrations)
        }
        guard case .migrationFailed(let version, let reason)? = error else {
            Issue.record("the broken migration was not reported as a failed migration: \(String(describing: error))")
            return nil
        }
        #expect(!reason.isEmpty)
        return version
    }

    @Test(
        "A migration that fails part-way is reported and rolled back; the data stays as it was and opens normally",
        arguments: Failure.allCases)
    func failedMigrationLeavesThePreviousData(_ failure: Failure) async throws {
        try await ScratchDirectory.with { scratch in
            let path = scratch.path("lisa.sqlite").path
            let latest = Migrations.latestVersion
            let written = try writeRecords(at: path, now: start)
            let before = try DatabaseContents(path: path)
            let identity = try FileIdentity(path: path)
            #expect(before.userVersion == latest)
            #expect(before.integrity == "ok")

            let attempt = start.addingTimeInterval(86_400)
            #expect(failedOpen(path, at: attempt, failure) == latest + 1)

            // The database is the same file, with the same schema version, schema objects and rows.
            let after = try DatabaseContents(path: path)
            #expect(after.userVersion == latest)
            #expect(after == before)
            #expect(after.integrity == "ok")
            #expect(try FileIdentity(path: path) == identity)
            #expect(identity.permissions == 0o600)
            // Nothing the failed migration created or added remains.
            #expect(after.probeObjects.isEmpty)
            #expect(!after.mentionsProbe)

            // The pre-migration copy exists beside the database and holds the same data.
            let copy = preMigrationCopy(of: path, version: latest, attempt: attempt)
            #expect(FileManager.default.fileExists(atPath: copy))
            #expect(try DatabaseContents(path: copy) == before)

            // The store opens normally again: no migration is pending, every record reads back as it was stored, and
            // the store accepts changes.
            let reopened = try LisaStorage.open(path: path, now: attempt.addingTimeInterval(60))
            #expect(reopened.migration.fromVersion == latest)
            #expect(reopened.migration.toVersion == latest)
            #expect(reopened.migration.preMigrationBackup == nil)
            try reopened.records.read { tx in
                for task in written.tasks {
                    #expect(try json(tx.require(LisaTask.self, id: task.id)) == json(task))
                }
                let idea = try tx.require(Idea.self, id: written.idea.id)
                #expect(idea.originalCapture == written.idea.originalCapture)
                #expect(try json(idea) == json(written.idea))
                #expect(try json(tx.require(Capture.self, id: written.capture.id)) == json(written.capture))
                let preference = try tx.require(Preference.self, id: written.preference.id)
                #expect(preference.revision == Revision(2))
                #expect(preference.value == .number(20))
            }
            #expect(try reopened.rawContent.get(written.raw) == written.rawBytes)
            let task = try #require(written.tasks.first)
            let changed = try reopened.records.write { tx -> LisaTask in
                var stored = try tx.require(LisaTask.self, id: task.id)
                stored.title = "Submit the synthetic grant report, revised"
                return try tx.update(stored)
            }
            #expect(changed.revision == task.revision.next)
            #expect(try reopened.records.read { try $0.require(LisaTask.self, id: task.id) }.title == changed.title)
            #expect(FileManager.default.fileExists(atPath: copy))
        }
    }

    /// What the owner had before the failed upgrade, read through the application once every change was made.
    private struct OwnerData {
        var task: LisaTask
        var capture: CaptureResult
        var preference: Preference
        var databasePath: String
    }

    /// The owner's idea, captured as written.
    private static let ideaText = "A synthetic idea: learn to build a canoe"

    /// Opens a host on `testHost`'s data directory, records a task, an idea capture and a preference as the owner, and
    /// closes the host again, as when it stops before an upgrade.
    private func recordOwnerData(_ testHost: TestHost) throws -> OwnerData {
        let host = try testHost.open()
        defer { host.close() }
        let app = host.application
        let created = try app.createTask(
            TaskDraft(
                title: "Send the synthetic quarterly invoice", priority: .high,
                deadline: SyntheticTask.due(TestTime.instant("2026-11-17T12:00", in: TestTime.newYork))),
            by: .localOwner)
        let capture = try app.capture(
            CaptureRequest(
                kind: .idea, text: Self.ideaText, channel: .commandLine, requestID: "failed-upgrade-idea-0001"),
            by: .localOwner)
        _ = try app.setPreference(.bufferMinutes, .number(25), expectedRevision: nil, by: .localOwner)
        let task = try #require(try app.record(LisaTask.self, id: created.id))
        let preference = try #require(try app.all(Preference.self).first { $0.key == .bufferMinutes })
        return OwnerData(task: task, capture: capture, preference: preference, databasePath: host.storage.path)
    }

    @Test("A failed upgrade tried twice keeps a copy each time, and the host then opens with all the owner's data")
    func failedUpgradeKeepsTheOwnersData() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let latest = Migrations.latestVersion
            let owner = try recordOwnerData(testHost)
            let path = owner.databasePath
            let before = try DatabaseContents(path: path)
            let identity = try FileIdentity(path: path)
            #expect(before.userVersion == latest)

            // The broken build is started twice, an hour apart; each start fails the same way and changes nothing. Its
            // failure does not depend on what the owner stored.
            var copies: [String] = []
            for hours in [1.0, 2.0] {
                let attempt = start.addingTimeInterval(hours * 3600)
                #expect(failedOpen(path, at: attempt, .missingTable) == latest + 1)
                #expect(try DatabaseContents(path: path) == before)
                #expect(try FileIdentity(path: path) == identity)
                copies.append(preMigrationCopy(of: path, version: latest, attempt: attempt))
            }
            // Both copies are kept, and each holds the data from before the attempts.
            let names = try scratch.fileNames(in: testHost.dataDirectory)
            let copyNames = names.filter { $0.hasPrefix("lisa.sqlite.pre-migration-") && $0.hasSuffix(".sqlite") }
            #expect(copyNames == copies.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted())
            for copy in copies {
                #expect(try DatabaseContents(path: copy) == before)
            }

            // The current build opens the same data directory normally, with everything the owner had.
            testHost.advance(minutes: 180)
            let host = try testHost.open()
            defer { host.close() }
            #expect(host.storage.migration.fromVersion == latest)
            #expect(host.storage.migration.toVersion == latest)
            let app = host.application
            let task = try #require(try app.record(LisaTask.self, id: owner.task.id))
            #expect(task.title == owner.task.title)
            #expect(task.priority == owner.task.priority)
            #expect(task.deadline == owner.task.deadline)
            #expect(task.status == owner.task.status)
            let ideaID = try #require(owner.capture.idea?.id)
            #expect(try app.record(Idea.self, id: ideaID)?.originalCapture == Self.ideaText)
            let preference = try #require(try app.all(Preference.self).first { $0.key == .bufferMinutes })
            #expect(preference.id == owner.preference.id)
            #expect(preference.value == .number(25))
            // Retrying the owner's capture after the failed upgrade returns the original capture, not a new one.
            let retried = try app.capture(
                CaptureRequest(
                    kind: .idea, text: Self.ideaText, channel: .commandLine, requestID: "failed-upgrade-idea-0001"),
                by: .localOwner)
            #expect(!retried.created)
            #expect(retried.capture.id == owner.capture.capture.id)
            #expect(try app.all(Idea.self).count == 1)
            for copy in copies {
                #expect(FileManager.default.fileExists(atPath: copy))
            }
        }
    }
}
