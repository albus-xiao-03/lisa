// Host operations behind CLI commands: one-off directory imports, backups and restores (CLI-01, CFG-03, DATA-05).

import Foundation
import LisaDomain
import LisaIngestion
import LisaLocalSources
import LisaPorts
import LisaRuntime
import LisaStore

extension LisaHost {
    /// Imports one local directory once, as source `key`, and applies the results. Re-importing the same files is
    /// deduplicated (L05).
    public func importDirectory(_ directory: URL, format: LocalSourceFormat, key: String, name: String) async throws
        -> SyncReport
    {
        let services = application.services
        let kind: SourceKind =
            switch format {
            case .mail: .localImport
            case .calendar: .calendarFeed
            case .feed: .newsFeed
            }
        let source = try services.sources.register(
            kind: kind, name: name, configurationKey: key, staleAfterSeconds: 6 * 3600)
        let connector = LocalDirectoryConnector(directory: directory, format: format)
        let runner = ConnectorRunner(store: storage.records, clock: services.clock, logger: logger)
        let report: SyncReport
        switch format {
        case .mail:
            report = await runner.synchronize(
                sourceID: source.id, connector: connector,
                processor: MailBatchProcessor(
                    store: storage.records, raw: storage.rawContent, settings: services.settings, clock: services.clock,
                    mailboxAddress: settings.emailSender.address, limits: settings.messageLimits),
                limits: settings.syncLimits)
        case .calendar:
            report = await runner.synchronize(
                sourceID: source.id, connector: connector,
                processor: CalendarBatchProcessor(
                    settings: services.settings, clock: services.clock, limits: settings.calendarLimits),
                limits: settings.syncLimits)
        case .feed:
            report = await runner.synchronize(
                sourceID: source.id, connector: connector,
                processor: NewsBatchProcessor(
                    store: storage.records, raw: storage.rawContent, clock: services.clock,
                    maxFeedBytes: settings.maxFeedBytes),
                limits: settings.syncLimits)
        }
        try application.ingested(report)
        return report
    }

    /// Writes a consistent backup with its manifest into `directory`.
    public func backup(to directory: URL) throws -> BackupManifest {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try storage.maintenance.backup(
            to: directory, now: application.services.clock.now(), applicationVersion: settings.applicationVersion)
    }

    /// Restores a backup into a data directory that no runtime holds. The replaced database is kept beside it.
    public static func restore(backupFile: URL, dataDirectory: URL, now: Date) throws -> RestoreReport {
        let lock = try DataDirectoryLock.acquire(directory: dataDirectory, mode: "restore", now: now)
        defer { lock.release() }
        return try StoreRestore.restore(
            backupFile: backupFile, databasePath: dataDirectory.appendingPathComponent("lisa.sqlite").path, now: now)
    }
}
