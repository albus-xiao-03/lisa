// The application facade: one entry point for every workflow, with principals and cross-service consequences.

import Foundation
import LisaAgenda
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaIngestion
import LisaLogging
import LisaOwnerData
import LisaPorts
import LisaReview
import LisaTime

/// The services the facade coordinates. Only the composition root builds this.
public struct LisaServices: Sendable {
    public var store: any RecordStore
    public var clock: any WallClock
    public var logger: Logger
    public var settings: any SettingsSource
    public var captures: CaptureService
    public var tasks: TaskService
    public var ideas: IdeaService
    public var preferences: PreferenceService
    public var deletion: DeletionService
    public var export: ExportService
    public var sources: SourceRegistry
    public var retention: RetentionService
    public var extraction: ExtractionService
    public var proposals: ProposalService
    public var outbox: DeliveryOutbox
    public var notifications: NotificationService
    public var reminders: ReminderService
    public var plans: PlanService
    public var briefs: BriefService
    public var devices: DeviceService
    /// Reads captured links' pages at the owner's request; `nil` when this host cannot (no network library).
    public var capturedPages: CapturedPageService?

    public init(
        store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource,
        captures: CaptureService, tasks: TaskService, ideas: IdeaService, preferences: PreferenceService,
        deletion: DeletionService, export: ExportService, sources: SourceRegistry, retention: RetentionService,
        extraction: ExtractionService, proposals: ProposalService, outbox: DeliveryOutbox,
        notifications: NotificationService, reminders: ReminderService, plans: PlanService, briefs: BriefService,
        devices: DeviceService, capturedPages: CapturedPageService? = nil
    ) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
        self.captures = captures
        self.tasks = tasks
        self.ideas = ideas
        self.preferences = preferences
        self.deletion = deletion
        self.export = export
        self.sources = sources
        self.retention = retention
        self.extraction = extraction
        self.proposals = proposals
        self.outbox = outbox
        self.notifications = notifications
        self.reminders = reminders
        self.plans = plans
        self.briefs = briefs
        self.devices = devices
        self.capturedPages = capturedPages
    }
}

/// What one maintenance cycle did.
public struct CycleReport: Sendable {
    public var review: ReviewReport
    public var proposalChanges: Int
    public var plan: Plan?
    public var reminders: ReminderSyncReport
    public var remindersFired: Int
    public var brief: Brief?
    public var deliveries: DeliveryRunSummary
}

/// The single facade used by the API router, the CLI and the demo.
public final class LisaApplication: Sendable {
    /// Calendar changes to events starting within this many hours are important enough to notify.
    public static let changeRelevanceHours = 48
    public let services: LisaServices
    /// Which APNs topics and environments device tokens may be registered for (from configuration).
    public let pushPolicy: PushRegistrationPolicy

    /// The default push policy accepts no tokens until APNs is configured.
    public init(
        services: LisaServices,
        pushPolicy: PushRegistrationPolicy = PushRegistrationPolicy(allowedTopics: [], allowedEnvironments: [])
    ) {
        self.services = services
        self.pushPolicy = pushPolicy
    }

    var store: any RecordStore { services.store }
    var clock: any WallClock { services.clock }

    /// Today's local date in the owner's timezone.
    public func today() throws -> LocalDate {
        ZoneRules.localDate(for: clock.now(), in: try services.settings.currentSettings().zone.timeZone)
    }

    // MARK: - Change propagation

    /// Applies the consequences of domain changes: important-change notifications for near calendar events,
    /// resolution of notifications for closed tasks, cancelled reminders, a recomputed plan and reminder sync.
    public func propagate(_ changes: [DomainChange]) throws {
        guard !changes.isEmpty else { return }
        let owner = try services.settings.currentSettings()
        let zone = owner.zone.timeZone
        let now = clock.now()
        try store.write { tx in
            for change in changes {
                switch change {
                case .occurrenceChanged(let id, _), .occurrenceCancelled(let id), .occurrenceRemoved(let id):
                    guard let occurrence = try tx.get(CalendarOccurrence.self, id: id),
                        occurrence.status != .tentative, Self.isNear(occurrence, now: now, zone: zone)
                    else { continue }
                    try services.notifications.importantChange(
                        .occurrence(id), changeSequence: occurrence.changeSequence, titleHint: occurrence.title,
                        settings: owner, in: tx)
                case .taskCompleted(let id), .taskCancelled(let id):
                    try NotificationService.resolve(
                        subjectKeys: [NotificationSubject.task(id).key], reason: "the task is closed", at: now, in: tx)
                default:
                    break
                }
            }
        }
        for change in changes {
            switch change {
            case .taskCompleted(let id):
                try services.reminders.cancelAll(subjectKey: "task:\(id.rawValue)", reason: "the task was completed")
            case .taskCancelled(let id):
                try services.reminders.cancelAll(
                    subjectKey: "task:\(id.rawValue)", reason: "the task was cancelled or deleted")
            default:
                break
            }
        }
        if changes.contains(where: \.affectsPlanning) {
            try services.plans.compute(for: ZoneRules.localDate(for: now, in: zone))
        }
        try services.reminders.sync()
    }

    static func isNear(_ occurrence: CalendarOccurrence, now: Date, zone: TimeZone) -> Bool {
        let range = occurrence.range(in: zone)
        return range.end >= now.addingTimeInterval(-3600)
            && range.start <= now.addingTimeInterval(TimeInterval(changeRelevanceHours * 3600))
    }

    /// Feeds a source synchronization's changes into the agenda.
    public func ingested(_ report: SyncReport) throws {
        try propagate(report.outcome.changes)
    }

    // MARK: - Maintenance cycle

    /// One pass of the host's work: review, matching, planning, reminders, the brief and the outbox. Each step
    /// persists its own results, so an interruption never loses completed work.
    public func runCycle(deliveryLimit: Int = 20) async throws -> CycleReport {
        let review = try await services.extraction.reviewPending()
        try propagate(review.changes)
        let proposalChanges = try services.proposals.rematch()
        try propagate(proposalChanges)
        let plan = try services.plans.compute(for: try today())
        let sync = try services.reminders.sync()
        let fired = try services.reminders.dispatchDue()
        let brief = try services.briefs.dispatchIfDue()
        let deliveries = try await services.outbox.runOnce(limit: deliveryLimit)
        return CycleReport(
            review: review, proposalChanges: proposalChanges.count, plan: plan, reminders: sync, remindersFired: fired,
            brief: brief, deliveries: deliveries)
    }

    /// Recovery after the host was unavailable (REM-04): expired leases, then missed reminders.
    public func recoverAfterDowntime() throws -> [String] {
        let leases = try services.outbox.recoverExpiredLeases()
        let decisions = try services.reminders.recover()
        var notes = decisions.filter { !$0.deliver }.map { "skipped reminder \($0.id.rawValue): \($0.reason)" }
        if leases.outcomeUnknown > 0 {
            notes.append("\(leases.outcomeUnknown) delivery attempt(s) had an unknown outcome and were not resent")
        }
        if leases.retried > 0 { notes.append("\(leases.retried) interrupted delivery attempt(s) will be retried") }
        return notes
    }
}
