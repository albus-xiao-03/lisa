// Recovery tests for L23, migration and restore (DATA-02, DATA-05, ARCH-03; D-22, D-23, D-36): a database the test
// builds in the version 1 schema, holding records written then, migrates when the host opens it, after a
// pre-migration copy, and stays usable (its delivery's payload key is backfilled, so completing the task suppresses
// it). A database from a newer schema is refused and left untouched. Restoring a backup brings back the backup's
// coherent state and keeps the replaced database; a restore is refused while a host holds the directory; and an
// older-schema backup is migrated forward when the restored directory is opened.

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

@Suite("L23 — Migration and restore", .tags(.recovery))
struct L23MigrationRestoreTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    /// Records as Lisa wrote them under schema version 1.
    private struct VersionOneRecords {
        var task: LisaTask
        var reminder: Reminder
        var delivery: Delivery
        var idea: Idea
        var capture: Capture
        var preference: Preference
    }

    /// Builds the version 1 schema at `path` with the version 1 migration, then writes `records` into its tables the
    /// way the store did then: `id`, `revision`, `updated_at`, the JSON body and the indexed columns that existed.
    private func buildVersionOne(at path: String, now: Date) throws -> VersionOneRecords {
        let built = try LisaStorage.open(path: path, now: now, migrations: [try #require(Migrations.all.first)])
        #expect(built.migration.toVersion == 1)
        let task = LisaTask(
            title: "Synthetic legacy filing", priority: .high,
            deadline: SyntheticTask.due(TestTime.instant("2026-11-17T10:00", in: TestTime.newYork)),
            confirmation: .confirmed, origin: .manual, now: now.addingTimeInterval(-86_400))
        var reminder = Reminder(
            subject: .task(task.id), rule: .deadlineAhead, dueAt: now.addingTimeInterval(-3600),
            occurrenceKey: "deadline:task:\(task.id.rawValue):0:legacy", subjectChangeSequence: 0, title: task.title,
            now: now.addingTimeInterval(-86_400))
        reminder.state = .delivered(at: now.addingTimeInterval(-3600))
        // The reminder's email copy, still pending when the old version stopped.
        let delivery = Delivery(
            channel: .email, recipient: .emailAddress(TestHost.ownerAddress), payload: .reminder(reminder.id),
            idempotencyKey: "email:legacy:\(reminder.id.rawValue):\(TestHost.ownerAddress)", mode: .dryRun,
            notBefore: now.addingTimeInterval(3600), validUntil: nil, now: now.addingTimeInterval(-3600))
        var capture = Capture(
            kind: .idea, text: "A synthetic legacy idea", url: nil, channel: .commandLine, principal: .localOwner,
            requestID: "legacy-capture-1", now: now.addingTimeInterval(-86_400))
        let idea = Idea(
            originalCapture: "A synthetic legacy idea", captureID: capture.id, now: now.addingTimeInterval(-86_400))
        capture.resultingIdeaID = idea.id
        capture.processing = .processed
        var preference = Preference(
            key: .bufferMinutes, value: .number(20), origin: .explicit, now: now.addingTimeInterval(-86_400))
        preference.confirmed = true
        let database = try SQLiteDatabase(path: path)
        try database.writeTransaction { session in
            try insert(task, into: session)
            try insert(reminder, into: session)
            try insert(delivery, into: session, without: ["payload_key"])
            try insert(idea, into: session)
            try insert(capture, into: session)
            try insert(preference, into: session)
        }
        return VersionOneRecords(
            task: task, reminder: reminder, delivery: delivery, idea: idea, capture: capture, preference: preference)
    }

    private func insert<E: StoredEntity>(_ entity: E, into session: SQLiteSession, without: Set<String> = []) throws {
        let indexes = E.indexes.map(\.name).filter { !without.contains($0) }
        let values = entity.indexValues
        let body = String(decoding: try DomainJSON.encoder().encode(entity), as: UTF8.self)
        let parameters: [SQLiteValue] =
            [
                .text(entity.id.description), .integer(entity.revision.value),
                .integer(entity.updatedAt.millisecondsSince1970), .text(body),
            ]
            + indexes.map { name -> SQLiteValue in
                switch values[name] ?? .null {
                case .text(let text): .text(text)
                case .integer(let number): .integer(number)
                case .null: .null
                }
            }
        let columns = (["id", "revision", "updated_at", "body"] + indexes).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: indexes.count + 4).joined(separator: ", ")
        _ = try session.query("INSERT INTO \(E.collectionName) (\(columns)) VALUES (\(placeholders))", parameters)
    }

    private func databasePath(_ testHost: TestHost) throws -> String {
        try SourceFiles.directory(testHost.dataDirectory)
        return testHost.dataDirectory.appendingPathComponent("lisa.sqlite").path
    }

    @Test("A version 1 database migrates when the host opens it, after a pre-migration copy, and stays usable")
    func versionOneDatabaseMigrates() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let path = try databasePath(testHost)
            let legacy = try buildVersionOne(at: path, now: start)

            let host = try testHost.open()
            let migration = host.storage.migration
            #expect(migration.fromVersion == 1)
            #expect(migration.toVersion == Migrations.latestVersion)
            let copy = try #require(migration.preMigrationBackup)
            #expect(FileManager.default.fileExists(atPath: copy))
            let app = host.application
            #expect(try app.record(LisaTask.self, id: legacy.task.id)?.title == legacy.task.title)
            #expect(try app.record(Reminder.self, id: legacy.reminder.id)?.state == legacy.reminder.state)
            #expect(try app.record(Idea.self, id: legacy.idea.id)?.originalCapture == "A synthetic legacy idea")
            #expect(try app.services.settings.currentSettings().planning.bufferMinutes == 20)
            // The payload key was backfilled from the stored record, so the delivery is found by its payload.
            let byPayload = try app.all(
                Delivery.self, RecordQuery.all.filter("payload_key", equals: "reminder:\(legacy.reminder.id.rawValue)"))
            #expect(byPayload.map(\.id) == [legacy.delivery.id])
            // Completing the task therefore suppresses the pending copy, which is never sent.
            _ = try app.setTaskStatus(legacy.task.id, to: .completed, expectedRevision: nil, by: .localOwner)
            testHost.advance(minutes: 61)
            await host.runtime.runOnce()
            #expect(try app.record(Delivery.self, id: legacy.delivery.id)?.state == .suppressed)
            #expect(try host.recorder.recent(limit: 100).filter { $0.subject?.hasPrefix("Reminder") == true }.isEmpty)
            // The capture's request ID still deduplicates a retry.
            let retried = try app.capture(
                CaptureRequest(
                    kind: .idea, text: "A synthetic legacy idea", channel: .commandLine, requestID: "legacy-capture-1"),
                by: .localOwner)
            #expect(!retried.created)
            #expect(retried.idea?.id == legacy.idea.id)
            host.close()
        }
    }

    @Test("A database from a newer schema is refused, and left as it was")
    func newerSchemaIsRefused() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let path = try databasePath(testHost)
            _ = try LisaStorage.open(path: path, now: start)
            let database = try SQLiteDatabase(path: path)
            try database.perform { try $0.setUserVersion(99) }
            #expect(throws: HostError.self) { _ = try testHost.open() }
            #expect(try database.perform { try $0.userVersion() } == 99)
            // The refusal released the lock: another attempt is refused for the same reason, not because it is held.
            #expect(throws: HostError.self) { _ = try testHost.open() }
        }
    }

    @Test("Restoring a backup brings back its coherent state and keeps the replaced database")
    func restoreBringsBackTheBackup() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            var host = try testHost.open()
            let app = host.application
            let kept = try app.createTask(
                TaskDraft(
                    title: "Synthetic kept task", priority: .high,
                    deadline: SyntheticTask.due(TestTime.instant("2026-11-18T10:00", in: TestTime.newYork))),
                by: .localOwner)
            let idea = try #require(
                try app.capture(
                    CaptureRequest(kind: .idea, text: "Synthetic kept idea", channel: .api), by: .localOwner
                )
                .idea)
            _ = try app.setPreference(.bufferMinutes, .number(10), expectedRevision: nil, by: .localOwner)
            await host.runtime.runOnce()
            let manifest = try host.backup(to: scratch.path("backups"))
            #expect(manifest.schemaVersion == Migrations.latestVersion)
            let backupFile = try #require(
                try scratch.fileNames(in: scratch.path("backups")).first { $0.hasSuffix(".sqlite") }
                    .map { scratch.path("backups", $0) })
            let remindersAtBackup = try app.all(Reminder.self).map(\.id).sorted()

            // Later changes, which the restore must undo.
            testHost.advance(minutes: 10)
            _ = try app.setTaskStatus(kept.id, to: .completed, expectedRevision: nil, by: .localOwner)
            _ = try app.delete(.idea(idea.id), by: .localOwner)
            _ = try app.createTask(TaskDraft(title: "Synthetic later task"), by: .localOwner)
            _ = try app.setPreference(.bufferMinutes, .number(30), expectedRevision: nil, by: .localOwner)
            // A restore is refused while the host holds the data directory.
            #expect(throws: (any Error).self) {
                _ = try LisaHost.restore(
                    backupFile: backupFile, dataDirectory: testHost.dataDirectory, now: testHost.clock.now())
            }
            host.close()

            let report = try LisaHost.restore(
                backupFile: backupFile, dataDirectory: testHost.dataDirectory, now: testHost.clock.now())
            let replaced = try #require(report.previousDatabaseMovedTo)
            #expect(FileManager.default.fileExists(atPath: replaced))
            host = try testHost.open()
            let restored = host.application
            try host.storage.maintenance.checkIntegrity()
            #expect(try restored.record(LisaTask.self, id: kept.id)?.status == .open)
            #expect(try restored.record(Idea.self, id: idea.id) != nil)
            #expect(try restored.all(LisaTask.self).map(\.title) == ["Synthetic kept task"])
            #expect(try restored.services.settings.currentSettings().planning.bufferMinutes == 10)
            #expect(try restored.all(Reminder.self).map(\.id).sorted() == remindersAtBackup)
            #expect(try restored.all(Reminder.self).allSatisfy { $0.state.name != "cancelled" })
            for (collection, count) in manifest.recordCounts where ["tasks", "ideas", "captures"].contains(collection) {
                let stored =
                    switch collection {
                    case "tasks": try restored.all(LisaTask.self).count
                    case "ideas": try restored.all(Idea.self).count
                    default: try restored.all(Capture.self).count
                    }
                #expect(stored == count, "\(collection)")
            }
            // The restored state keeps working without duplicating anything.
            await host.runtime.runOnce()
            #expect(try restored.all(Reminder.self).map(\.id).sorted() == remindersAtBackup)
            host.close()
        }
    }

    @Test("A restored backup from the version 1 schema is migrated forward when the directory is opened")
    func olderBackupMigratesAfterRestore() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let backups = try SourceFiles.directory(scratch.path("backups"))
            let backupFile = backups.appendingPathComponent("lisa-backup-legacy.sqlite")
            let legacy = try buildVersionOne(at: backupFile.path, now: start)
            let manifest = BackupManifest(
                format: SQLiteStoreMaintenance.backupFormat, schemaVersion: 1, createdAt: start,
                applicationVersion: "0.0.0-legacy", recordCounts: [:])
            try DomainJSON.encoder().encode(manifest).write(to: backupFile.appendingPathExtension("manifest.json"))
            try SourceFiles.directory(testHost.dataDirectory)

            let report = try LisaHost.restore(
                backupFile: backupFile, dataDirectory: testHost.dataDirectory, now: testHost.clock.now())
            #expect(report.restoredSchemaVersion == 1)
            let host = try testHost.open()
            #expect(host.storage.migration.fromVersion == 1)
            #expect(host.storage.migration.toVersion == Migrations.latestVersion)
            #expect(host.storage.migration.preMigrationBackup != nil)
            #expect(try host.application.record(LisaTask.self, id: legacy.task.id)?.title == legacy.task.title)
            host.close()
        }
    }
}
