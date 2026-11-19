// The host runtime (OPS-01): bounded cycles of source synchronization, application work and maintenance.

import Foundation
import LisaApplication
import LisaDomain
import LisaIngestion
import LisaLogging
import LisaOwnerData
import LisaTime
import Synchronization

/// Runtime settings from the validated configuration.
public struct RuntimeOptions: Sendable {
    /// Time between cycles when nothing is due sooner.
    public var cycleInterval: TimeInterval
    /// Sources synchronized at the same time (OPS-02 concurrent network requests).
    public var maxConcurrentSources: Int
    public var retry: RetrySchedule
    public var retention: RetentionSettings
    /// Time between maintenance passes (retention, request-ledger pruning).
    public var maintenanceInterval: TimeInterval
    /// Deliveries processed per cycle.
    public var deliveriesPerCycle: Int

    public init(
        cycleInterval: TimeInterval = 300, maxConcurrentSources: Int = 4, retry: RetrySchedule = RetrySchedule(),
        retention: RetentionSettings = RetentionSettings(), maintenanceInterval: TimeInterval = 86_400,
        deliveriesPerCycle: Int = 20
    ) {
        self.cycleInterval = cycleInterval
        self.maxConcurrentSources = maxConcurrentSources
        self.retry = retry
        self.retention = retention
        self.maintenanceInterval = maintenanceInterval
        self.deliveriesPerCycle = deliveriesPerCycle
    }
}

/// Health facts the runtime reports.
public struct RuntimeHealth: Hashable, Sendable {
    public var startedAt: Date
    public var lastCycleAt: Date?
    public var lastCycleProblem: String?
    public var warnings: [String]
    public var cycles: Int
}

/// What one cycle did.
public struct CycleOutcome: Sendable {
    public var synchronized: [SyncReport]
    public var cycle: CycleReport?
    public var problem: String?
    public var maintenance: RetentionReport?
}

/// Drives the host. Exactly one runtime runs per data directory; the caller holds the `DataDirectoryLock`.
public final class HostRuntime: Sendable {
    public let application: LisaApplication
    let runner: ConnectorRunner
    let jobs: [SourceJob]
    let schedule: ScheduleStore
    let options: RuntimeOptions
    let logger: Logger
    let random: @Sendable () -> Double
    private let healthState: Mutex<RuntimeHealth>

    public init(
        application: LisaApplication, jobs: [SourceJob], schedule: ScheduleStore, options: RuntimeOptions,
        logger: Logger, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.application = application
        self.runner = ConnectorRunner(
            store: application.services.store, clock: application.services.clock, logger: logger)
        self.jobs = jobs
        self.schedule = schedule
        self.options = options
        self.logger = logger
        self.random = random
        self.healthState = Mutex(
            RuntimeHealth(
                startedAt: application.services.clock.now(), lastCycleAt: schedule.load().lastCycleAt,
                lastCycleProblem: nil, warnings: [], cycles: 0))
    }

    public func health() -> RuntimeHealth {
        healthState.withLock { $0 }
    }

    /// Recovers after downtime (REM-04): expired delivery leases first, then missed reminders. Returns what was
    /// skipped and why.
    public func recover() throws -> [String] {
        let notes = try application.recoverAfterDowntime()
        for note in notes { logger.notice("recovery", ["note": .public(note)]) }
        healthState.withLock { $0.warnings = Array(notes.prefix(10)) }
        return notes
    }

    /// One bounded cycle: due sources (isolated from each other), then application work, then maintenance when due.
    @discardableResult
    public func runOnce() async -> CycleOutcome {
        let clock = application.services.clock
        var state = schedule.load()
        let now = clock.now()
        let due = jobs.filter { (state.jobs[$0.key]?.nextRunAt ?? .distantPast) <= now }
        var reports: [SyncReport] = []
        for batch in stride(from: 0, to: due.count, by: max(1, options.maxConcurrentSources)) {
            let slice = Array(due[batch..<min(due.count, batch + max(1, options.maxConcurrentSources))])
            let results = await withTaskGroup(of: (String, SyncReport).self) { group in
                for job in slice { group.addTask { (job.key, await job.synchronize(self.runner)) } }
                var collected: [(String, SyncReport)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (key, report) in results {
                reports.append(report)
                state.jobs[key] = nextState(for: key, report: report, previous: state.jobs[key], now: clock.now())
                do {
                    try application.ingested(report)
                } catch {
                    logger.error("applying a synchronization failed", ["source": .public(key)])
                }
            }
        }
        var outcome = CycleOutcome(synchronized: reports, cycle: nil, problem: nil, maintenance: nil)
        do {
            outcome.cycle = try await application.runCycle(deliveryLimit: options.deliveriesPerCycle)
        } catch {
            outcome.problem = "the processing cycle failed: \(String(describing: error).prefix(200))"
            logger.error("cycle failed", ["error": .private(String(describing: error))])
        }
        if (state.lastMaintenanceAt ?? .distantPast).addingTimeInterval(options.maintenanceInterval) <= clock.now() {
            do {
                outcome.maintenance = try application.services.retention.prune(options.retention)
                try application.pruneRequestLedger()
                state.lastMaintenanceAt = clock.now()
            } catch {
                logger.warning("maintenance failed; it runs again next cycle", [:])
            }
        }
        state.lastCycleAt = clock.now()
        do { try schedule.save(state) } catch { logger.warning("the runtime state could not be saved", [:]) }
        let finishedAt = clock.now()
        let problem = outcome.problem
        healthState.withLock { health in
            health.lastCycleAt = finishedAt
            health.lastCycleProblem = problem
            health.cycles += 1
        }
        return outcome
    }

    func nextState(for key: String, report: SyncReport, previous: JobState?, now: Date) -> JobState {
        guard let job = jobs.first(where: { $0.key == key }) else { return JobState(nextRunAt: now) }
        if let failure = report.failure {
            let failures = (previous?.consecutiveFailures ?? 0) + 1
            let next = options.retry.nextRun(
                after: now, failures: failures, retryAfter: failure.retryAfter, random: random())
            return JobState(
                nextRunAt: next, consecutiveFailures: failures, lastRunAt: now, lastOutcome: failure.errorClass.rawValue
            )
        }
        let next = report.morePending ? now : now.addingTimeInterval(job.interval)
        return JobState(
            nextRunAt: next, consecutiveFailures: 0, lastRunAt: now,
            lastOutcome: report.skippedDisabled ? "disabled" : "ok")
    }

    /// The time until the next job or cycle is due, bounded between 15 seconds and the cycle interval.
    public func delayUntilNextWork() -> TimeInterval {
        let now = application.services.clock.now()
        let state = schedule.load()
        let nextJob =
            jobs.compactMap { state.jobs[$0.key]?.nextRunAt }.min() ?? now.addingTimeInterval(options.cycleInterval)
        return min(max(15, nextJob.timeIntervalSince(now)), options.cycleInterval)
    }

    /// Runs cycles until the task is cancelled (graceful shutdown finishes the current cycle first).
    public func run() async {
        while !Task.isCancelled {
            await runOnce()
            do {
                try await Task.sleep(for: .seconds(delayUntilNextWork()))
            } catch {
                break
            }
        }
        logger.notice("runtime stopped", ["cycles": .count(health().cycles)])
    }
}
