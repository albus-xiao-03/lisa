// The composition root (plan §5.2): lock, logging, store, adapters, services, application, runtime and router.

import Foundation
import LisaAPI
import LisaAPIContract
import LisaAgenda
import LisaApplication
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaInference
import LisaIngestion
import LisaLocalSources
import LisaLogging
import LisaOwnerData
import LisaPorts
import LisaReview
import LisaRuntime
import LisaSecrets
import LisaStore
import LisaTime

/// A running host. Opening it takes the data-directory lock; `close()` releases it. While a host is open, no other
/// runtime can write the same data directory (ARCH-03).
public final class LisaHost: Sendable {
    public let settings: HostSettings
    public let storage: LisaStorage
    public let application: LisaApplication
    public let runtime: HostRuntime
    public let router: APIRouter
    public let recorder: any DryRunRecorder
    public let logger: Logger
    /// What recovery after the previous run skipped and why (REM-04).
    public let recoveryNotes: [String]
    /// Configured capabilities that are not available in this build, for `lisa doctor` and health.
    public let unavailable: [String]
    /// The owner credential of the loopback owner listener while the network API is served.
    public let ownerAccess: OwnerAccess
    /// Resolves secret references, such as the API's TLS identity.
    let secrets: any SecretStore
    let lock: DataDirectoryLock

    /// Opens the host in the order of plan §5.2 and recovers after any downtime.
    public static func open(settings: HostSettings, platform: HostPlatform) throws -> LisaHost {
        let clock = platform.clock
        let lock = try DataDirectoryLock.acquire(
            directory: settings.dataDirectory, mode: platform.mode, now: clock.now())
        do {
            return try LisaHost(settings: settings, platform: platform, lock: lock)
        } catch {
            lock.release()
            throw error
        }
    }

    private init(settings: HostSettings, platform: HostPlatform, lock: DataDirectoryLock) throws {
        let clock = platform.clock
        let directory = settings.dataDirectory
        var sinks: [any LogSink] = [
            try RotatingFileSink(
                directory: directory.appendingPathComponent("logs"), maxBytes: settings.logMaxBytes,
                keepFiles: settings.logKeepFiles)
        ]
        if platform.logToStandardError { sinks.append(StandardErrorSink()) }
        let logger = Logger(category: "lisa", sink: MultiplexSink(sinks))
        let adapters = HostAdapters(settings: settings, platform: platform)
        let live = try adapters.liveTransports()
        let storage: LisaStorage
        do {
            storage = try LisaStorage.open(path: directory.appendingPathComponent("lisa.sqlite").path, now: clock.now())
        } catch {
            throw HostError.storeUnavailable(String(describing: error))
        }
        let store = storage.records
        let raw = storage.rawContent
        let base = settings.ownerSettings
        let effective = EffectiveSettings(base: { base }, store: store, logger: logger)
        let recorder = try FileDryRunRecorder(directory: directory, capacity: settings.dryRunCaptureLimit)
        let devices = DeviceService(store: store, clock: clock, logger: logger)
        let outbox = DeliveryOutbox(
            store: store, clock: clock, logger: logger, settings: effective, content: AgendaContent(store: store),
            live: live, recorder: recorder,
            tokenFeedback: devices, sender: settings.emailSender)
        let notifications = NotificationService(clock: clock, logger: logger, outbox: outbox)
        var unavailable: [String] = []
        let (provider, modelNote) = adapters.modelProvider()
        if let modelNote { unavailable.append(modelNote) }
        let capturedPages: CapturedPageService?
        switch adapters.capturedPageRetrieval() {
        case .success(let retrieval):
            capturedPages = CapturedPageService(
                store: store, raw: raw, clock: clock, logger: logger, retrieval: retrieval)
        case .failure(let reason):
            capturedPages = nil
            unavailable.append("reading captured links is unavailable: \(reason)")
        }
        let services = LisaServices(
            store: store, clock: clock, logger: logger, settings: effective,
            captures: CaptureService(store: store, clock: clock, logger: logger),
            tasks: TaskService(store: store, clock: clock, logger: logger),
            ideas: IdeaService(store: store, clock: clock, logger: logger),
            preferences: PreferenceService(store: store, clock: clock, logger: logger),
            deletion: DeletionService(store: store, raw: raw, clock: clock, logger: logger),
            export: ExportService(store: store, clock: clock, logger: logger),
            sources: SourceRegistry(store: store, raw: raw, clock: clock, logger: logger),
            retention: RetentionService(store: store, raw: raw, clock: clock, logger: logger),
            extraction: ExtractionService(
                store: store, clock: clock, logger: logger, settings: effective,
                pipeline: ExtractionPipeline(
                    provider: provider, sharing: settings.dataSharing, limits: settings.modelLimits,
                    budget: Self.modelBudget(for: settings, clock: clock))),
            proposals: ProposalService(store: store, clock: clock, logger: logger, settings: effective),
            outbox: outbox, notifications: notifications,
            reminders: ReminderService(
                store: store, clock: clock, logger: logger, settings: effective, notifications: notifications,
                outbox: outbox),
            plans: PlanService(store: store, clock: clock, logger: logger, settings: effective),
            briefs: BriefService(
                store: store, clock: clock, logger: logger, settings: effective, notifications: notifications,
                outbox: outbox),
            devices: devices, capturedPages: capturedPages)
        let application = LisaApplication(services: services, pushPolicy: settings.pushPolicy)
        let (jobs, notes) = try Self.jobs(
            for: settings, adapters: adapters, services: services, store: store, raw: raw, settings: effective)
        unavailable += notes
        let runtime = HostRuntime(
            application: application, jobs: jobs, schedule: ScheduleStore(directory: directory),
            options: settings.runtime,
            logger: logger)
        let ownerAccess = OwnerAccess()
        let router = APIRouter(
            application: application,
            configuration: RouterConfiguration(
                applicationVersion: settings.applicationVersion, schemaVersion: Migrations.latestVersion,
                idempotencyRetentionDays: settings.idempotencyRetentionDays,
                requestsPerMinute: settings.requestsPerMinute,
                ownerCredentialVerifier: { ownerAccess.verify($0) },
                localNotificationsLive: platform.localNotifications != nil,
                model: HostModelStatus.status(of: settings.model, provider: provider, limits: settings.modelLimits)),
            status: RuntimeStatusBridge(runtime: runtime), logger: logger)
        self.settings = settings
        self.storage = storage
        self.application = application
        self.runtime = runtime
        self.router = router
        self.recorder = recorder
        self.logger = logger
        self.lock = lock
        self.unavailable = unavailable
        self.ownerAccess = ownerAccess
        self.secrets = platform.secrets
        self.recoveryNotes = try runtime.recover()
        logger.notice(
            "host opened",
            ["mode": .public(platform.mode), "sources": .count(jobs.count), "schema": .count(Migrations.latestVersion)])
    }

    /// Registers configured sources and builds a synchronization job for each one. A source whose adapter cannot be
    /// built is registered and marked failing, never silently skipped.
    static func jobs(
        for settings: HostSettings, adapters: HostAdapters, services: LisaServices, store: any RecordStore,
        raw: any RawContentStore, settings effective: any SettingsSource
    ) throws -> ([SourceJob], [String]) {
        var jobs: [SourceJob] = []
        var notes: [String] = []
        let clock = services.clock
        for source in settings.sources {
            let record = try services.sources.register(
                kind: source.kind, name: source.name, configurationKey: source.key,
                staleAfterSeconds: source.staleAfterSeconds)
            guard source.enabled else { continue }
            let connector: any SourceConnector
            switch adapters.connector(for: source.access) {
            case .success(let built):
                connector = built
            case .failure(let reason):
                notes.append("\(source.name): the \(source.access.adapterName) adapter cannot be used: \(reason)")
                try markUnavailable(record.id, reason: "\(reason)", store: store, clock: clock)
                continue
            }
            let interval = TimeInterval(source.syncIntervalSeconds)
            switch Self.contentKind(of: source.access) {
            case .mail:
                jobs.append(
                    SourceJob(
                        key: source.key, sourceID: record.id, interval: interval, connector: connector,
                        processor: MailBatchProcessor(
                            store: store, raw: raw, settings: effective, clock: clock,
                            mailboxAddress: source.mailboxAddress ?? settings.emailSender.address,
                            limits: settings.messageLimits),
                        limits: settings.syncLimits))
            case .calendar:
                jobs.append(
                    SourceJob(
                        key: source.key, sourceID: record.id, interval: interval, connector: connector,
                        processor: CalendarBatchProcessor(
                            settings: effective, clock: clock, limits: settings.calendarLimits,
                            floatingZone: source.floatingTimeZone),
                        limits: settings.syncLimits))
            case .feed:
                jobs.append(
                    SourceJob(
                        key: source.key, sourceID: record.id, interval: interval, connector: connector,
                        processor: NewsBatchProcessor(
                            store: store, raw: raw, clock: clock, maxFeedBytes: settings.maxFeedBytes),
                        limits: settings.syncLimits))
            }
        }
        return (jobs, notes)
    }

    /// Which ingestion path a source's items take.
    static func contentKind(of access: SourceAccess) -> LocalSourceFormat {
        switch access {
        case .localDirectory(_, let format), .localFile(_, let format): format
        case .imapMailbox: .mail
        case .calendarSubscription: .calendar
        case .newsFeed, .xAccount, .discordChannel: .feed
        }
    }

    /// Records that a source cannot be synchronized because its adapter is unavailable.
    private static func markUnavailable(_ id: SourceID, reason: String, store: any RecordStore, clock: any WallClock)
        throws
    {
        try store.write { tx in
            guard var current = try tx.get(Source.self, id: id) else { return }
            let now = clock.now()
            current.lastFailure = SourceFailure(
                errorClass: .unsupported, summary: "the adapter is unavailable: \(reason)", occurredAt: now)
            current.lastAttemptAt = now
            current.updatedAt = now
            try tx.update(current)
        }
    }

    /// The persisted daily request count for a model endpoint (MODEL-01). The offline deterministic provider sends
    /// nothing anywhere, so it is not counted.
    static func modelBudget(for settings: HostSettings, clock: any WallClock) -> (any ModelRequestBudget)? {
        guard case .openAICompatible = settings.model else { return nil }
        return FileModelRequestBudget(
            directory: settings.dataDirectory, clock: clock, zone: settings.ownerSettings.zone.timeZone)
    }

    /// A transport that acts as the local owner (the Mac app's embedded mode, the CLI, the demo).
    public var ownerTransport: InProcessTransport {
        InProcessTransport(router: router, origin: .trustedLocalOwner)
    }

    /// A transport that authenticates each request by its device credential, as the network server does.
    public var deviceTransport: InProcessTransport {
        InProcessTransport(router: router, origin: .authenticateHeaders(isLoopback: true))
    }

    /// Releases the data-directory lock. The store closes when the host is released.
    public func close() {
        logger.notice("host closed", [:])
        lock.release()
    }
}
