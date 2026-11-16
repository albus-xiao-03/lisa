// The offline end-to-end demonstration (DEMO-01): ingest, review, plan, brief, dry-run delivery to two synthetic
// devices, cross-device acknowledgement and completion, and a restart without duplicate side effects.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaClient
import LisaDomain
import LisaFixtures
import LisaHost
import LisaPorts
import LisaRuntime
import LisaSecrets
import LisaTime

/// Why the demonstration could not run.
public enum DemoError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The demonstration only writes to a new or empty directory, so it can never touch real Lisa data.
    case directoryNotEmpty(String)
    case fixturesMissing

    public var description: String {
        switch self {
        case .directoryNotEmpty(let path):
            "the demo needs a new or empty data directory; \(path) already contains files"
        case .fixturesMissing:
            "the demonstration fixtures are missing (the Lisa_LisaFixtures resource bundle was not found)"
        }
    }
}

/// Runs the scenario against its own data directory with a fixed clock (2026-11-16 08:00 America/New_York).
public enum DemoScenario {
    static let iPhoneInstallation = "demo-iphone-installation"
    static let iPadInstallation = "demo-ipad-installation"

    public static func run(dataDirectory: URL, applicationVersion: String, fixturesRoot: URL? = nil) async throws
        -> DemoReport
    {
        guard let root = fixturesRoot ?? LisaFixtures.root else { throw DemoError.fixturesMissing }
        try prepare(dataDirectory)
        let fixtures = DemoFixtures(root: root)
        let clock = ManualWallClock(DemoConstants.start)
        let settings = DemoConstants.hostSettings(
            dataDirectory: dataDirectory, fixtures: fixtures, applicationVersion: applicationVersion)
        let platform = HostPlatform(clock: clock, secrets: EnvironmentSecretStore(environment: [:]), mode: "demo")
        var steps: [DemoStep] = []

        var host = try LisaHost.open(settings: settings, platform: platform)
        let owner = LisaAPIClient(
            transport: host.ownerTransport, credentials: DemoCredentialStore(installationID: "demo-owner"),
            requiresPairing: false)
        let setup = try await setUp(owner: owner, host: host, fixtures: fixtures)
        let outcome = await host.runtime.runOnce()

        steps.append(try ingestion(host: host, outcome: outcome))
        steps.append(try await persistence(host: host, owner: owner, setup: setup))
        steps.append(try await proposals(owner: owner))
        steps.append(try await rundown(owner: owner))
        steps.append(try await brief(owner: owner))
        steps.append(try await deliveries(host: host, owner: owner))
        steps.append(try await acknowledgement(host: host, clock: clock, setup: setup))

        let before = try Counts(host: host)
        host.close()
        clock.advance(by: 60)
        host = try LisaHost.open(settings: settings, platform: platform)
        let restarted = await host.runtime.runOnce()
        let after = try Counts(host: host)
        steps.append(restart(before: before, after: after, outcome: restarted, notes: host.recoveryNotes))
        host.close()
        return DemoReport(label: DemoConstants.label, dataDirectory: dataDirectory.path, steps: steps)
    }

    static func prepare(_ directory: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            guard try manager.contentsOfDirectory(atPath: directory.path).isEmpty else {
                throw DemoError.directoryNotEmpty(directory.path)
            }
        }
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("Lisa demonstration data directory: synthetic data only.\n".utf8).write(
            to: directory.appendingPathComponent("DEMONSTRATION.txt"))
    }

    // MARK: - Setup

    struct Setup {
        var iPhone: LisaAPIClient
        var iPad: LisaAPIClient
        var iPhoneID: String
        var iPadID: String
        var preferencesApplied: Int
        var ideaID: String?
    }

    /// Explicit preferences, a captured idea made available for planning, and two paired synthetic devices.
    static func setUp(owner: LisaAPIClient, host: LisaHost, fixtures: DemoFixtures) async throws -> Setup {
        struct FixturePreference: Decodable {
            var key: String
            var value: PreferenceValueDTO
        }
        let preferences = try JSONDecoder().decode(
            [FixturePreference].self, from: Data(contentsOf: fixtures.preferences))
        _ = try await owner.updatePreferences(
            PreferencesPatchRequest(changes: preferences.map { PreferenceChange(key: $0.key, value: $0.value) }),
            requestID: "demo-preferences-0001")
        let ideaText = try String(contentsOf: fixtures.idea, encoding: .utf8).trimmingCharacters(
            in: .whitespacesAndNewlines)
        let capture = try await owner.capture(
            CaptureRequestDTO(kind: .idea, text: ideaText, channel: .demonstration), requestID: "demo-idea-capture-0001"
        )
        if let ideaID = capture.ideaID {
            let idea = try await owner.ideas().items.first { $0.id == ideaID }
            if let idea, idea.lifecycle == .inbox {
                _ = try await owner.updateIdea(
                    id: ideaID, IdeaPatchRequest(expectedRevision: idea.revision, lifecycle: .availableForPlanning),
                    requestID: "demo-idea-plan-0001")
            }
        }
        let (iPhone, iPhoneID) = try await pair(
            owner: owner, host: host, name: "Demo iPhone", deviceClass: .iPhone, installation: iPhoneInstallation,
            token: String(repeating: "a1", count: 32))
        let (iPad, iPadID) = try await pair(
            owner: owner, host: host, name: "Demo iPad", deviceClass: .iPad, installation: iPadInstallation,
            token: String(repeating: "b2", count: 32))
        return Setup(
            iPhone: iPhone, iPad: iPad, iPhoneID: iPhoneID, iPadID: iPadID, preferencesApplied: preferences.count,
            ideaID: capture.ideaID)
    }

    /// Pairs a synthetic device through the same API path a real device uses, registers a synthetic token and
    /// reports notifications as allowed.
    static func pair(
        owner: LisaAPIClient, host: LisaHost, name: String, deviceClass: DeviceClassValue, installation: String,
        token: String
    ) async throws -> (LisaAPIClient, String) {
        let client = LisaAPIClient(
            transport: host.deviceTransport, credentials: DemoCredentialStore(installationID: installation))
        let code = try await owner.createPairingCode(requestID: "demo-code-\(installation)")
        let device = try await client.pair(
            PairDeviceRequest(
                code: code.code, installationID: installation, name: name, deviceClass: deviceClass,
                appBundleID: DemoConstants.appTopic, environment: .development))
        _ = try await client.registerPush(
            PushRegistrationRequest(token: token, environment: .development, topic: DemoConstants.appTopic))
        _ = try await client.reportNotificationStatus(NotificationStatusRequest(authorization: .authorized))
        return (client, device.id)
    }

    // MARK: - Steps

    static func ingestion(host: LisaHost, outcome: LisaRuntime.CycleOutcome) throws -> DemoStep {
        var details: [String] = []
        for report in outcome.synchronized {
            let name = try host.application.record(Source.self, id: report.sourceID)?.name ?? "source"
            if let failure = report.failure {
                details.append("\(name): failed (\(failure.errorClass.rawValue)): \(failure.summary)")
            } else {
                details.append(
                    "\(name): \(report.outcome.inserted) new, \(report.outcome.unchanged) already known, "
                        + "\(report.outcome.updated) changed")
            }
        }
        let emails = try host.application.all(EmailMessage.self)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: host.settings.sources[0].localDirectoryPath ?? ""
        )
        .filter { $0.hasSuffix(".eml") }
        let sources = try host.application.all(Source.self)
        let unavailable = sources.first { $0.configurationKey == "demo-unavailable" }
        return DemoStep(
            number: 1, title: "Ingest and deduplicate", details: details,
            checks: [
                DemoCheck(
                    "\(files.count) mail files stored as \(emails.count) messages (the duplicate is dropped)",
                    emails.count == files.count - 1),
                DemoCheck(
                    "the calendar's occurrences are stored", try !host.application.all(CalendarOccurrence.self).isEmpty),
                DemoCheck("feed items are stored", try !host.application.all(NewsItem.self).isEmpty),
                DemoCheck("the unavailable source is recorded as failing", unavailable?.isFailing == true),
                DemoCheck("the processing cycle completed", outcome.problem == nil),
            ])
    }

    static func persistence(host: LisaHost, owner: LisaAPIClient, setup: Setup) async throws -> DemoStep {
        let counts = try Counts(host: host)
        let tasks = try await owner.tasks().items
        return DemoStep(
            number: 2, title: "Persist results",
            details: [
                "stored: \(counts.emails) messages, \(counts.tasks) tasks, \(counts.proposals) event proposals, "
                    + "\(counts.occurrences) calendar occurrences, \(counts.news) news items, \(counts.ideas) idea",
                "explicit preferences applied: \(setup.preferencesApplied)",
            ] + tasks.map { "task: \($0.title) [\($0.confirmation.rawValue)]" },
            checks: [
                DemoCheck("the captured idea is saved as written", setup.ideaID != nil && counts.ideas == 1),
                DemoCheck(
                    "confirmed tasks come only from the owner's own words", try injectionTasksUnconfirmed(host: host)),
                DemoCheck(
                    "two synthetic devices are paired", try host.application.all(DeviceRegistration.self).count == 2),
            ])
    }

    static func proposals(owner: LisaAPIClient) async throws -> DemoStep {
        let proposals = try await owner.proposals().items
        return DemoStep(
            number: 3, title: "Identify event proposals",
            details: proposals.map { proposal in
                let when = proposal.timing.start.map(APIDates.string(from:)) ?? proposal.timing.date ?? "date unknown"
                return "proposal: \(proposal.title) at \(when) — \(proposal.match.state)"
            },
            checks: [
                DemoCheck(
                    "the forwarded message's possible event is a proposal",
                    proposals.contains { $0.title.lowercased().contains("budget review") }),
                DemoCheck(
                    "the attached invitation is a proposal",
                    proposals.contains { $0.title.lowercased().contains("design review") }),
                DemoCheck(
                    "no proposal was added to a calendar by Lisa", proposals.allSatisfy { $0.match.state != "matched" }),
            ])
    }

    static func rundown(owner: LisaAPIClient) async throws -> DemoStep {
        let plan = try await owner.rundown()
        let blocks = plan.blocks.filter { $0.state != "rejected" }.sorted { $0.start < $1.start }
        let timedBlocks = blocks.filter { $0.kind != "fixedEvent" }
        let overlapping = zip(timedBlocks, timedBlocks.dropFirst()).contains { $0.end > $1.start }
        let zone = TimeZone(identifier: DemoConstants.zone.identifier)!
        var details = blocks.map { block in
            "\(clockTime(block.start, zone))–\(clockTime(block.end, zone)) \(block.title) (\(block.kind), \(block.state))"
        }
        details += plan.unscheduled.map { "not scheduled: \($0.title): \($0.reason)" }
        return DemoStep(
            number: 4, title: "Produce a feasible rundown", details: details,
            checks: [
                DemoCheck("calendar events are in the rundown", blocks.contains { $0.kind == "fixedEvent" }),
                DemoCheck("tasks are planned", blocks.contains { $0.kind == "task" }),
                DemoCheck("planned blocks do not overlap", !overlapping),
            ])
    }

    static func brief(owner: LisaAPIClient) async throws -> DemoStep {
        let brief = try await owner.brief()
        let preview = brief.text.split(separator: "\n").prefix(12).map(String.init)
        return DemoStep(
            number: 5, title: "Produce readable and spoken briefs",
            details: preview + ["spoken (\(brief.estimatedSpokenSeconds) s): \(String(brief.spokenText.prefix(240)))…"],
            checks: [
                DemoCheck("the readable brief has content", !brief.text.isEmpty),
                DemoCheck(
                    "the spoken brief has content and no links",
                    !brief.spokenText.isEmpty && !brief.spokenText.contains("http")),
                DemoCheck(
                    "every item cites its evidence",
                    brief.items.allSatisfy { $0.section == "sourceHealth" || !$0.references.isEmpty }),
                DemoCheck("the unavailable source is reported", brief.text.contains("Demo unavailable feed")),
            ])
    }

    static func deliveries(host: LisaHost, owner: LisaAPIClient) async throws -> DemoStep {
        let captures = try host.recorder.recent(limit: 200)
        let emails = captures.filter { $0.channel == .email }
        let pushes = captures.filter { $0.channel == .push }
        let all = try host.application.all(Delivery.self)
        let addresses = try await owner.preferences().filter { $0.key == "delivery.approvedEmailAddresses" }
        return DemoStep(
            number: 6, title: "Capture intended deliveries as dry runs",
            details: captures.prefix(8).map {
                "captured \($0.channel.rawValue) to \($0.recipient): \($0.subject ?? "")"
            },
            checks: [
                DemoCheck(
                    "the brief email went only to the approved address",
                    !emails.isEmpty && emails.allSatisfy { $0.recipient == DemoConstants.ownerAddress }),
                DemoCheck("both devices received the reminder and the brief notification", pushes.count >= 4),
                DemoCheck(
                    "nothing was addressed to the injected recipient or number",
                    !captures.contains { $0.recipient.contains("example.net") || $0.recipient.contains("5550177") }),
                DemoCheck("the injection did not change approved recipients", addresses.isEmpty),
                DemoCheck("no delivery was sent live", all.allSatisfy { $0.mode == .dryRun }),
            ])
    }

    /// At 09:00 the 08:45 task is overdue. The overdue notification is recorded for both devices; the iPad
    /// acknowledges it through its client before the outbox runs, so the iPhone's pending delivery is suppressed.
    /// The iPhone then completes the task, which cancels its remaining reminders.
    static func acknowledgement(host: LisaHost, clock: ManualWallClock, setup: Setup) async throws -> DemoStep {
        clock.set(DemoConstants.start.addingTimeInterval(3_600))
        try host.application.services.reminders.sync()
        _ = try host.application.services.reminders.dispatchDue()
        let overdue = try host.application.all(NotificationIntent.self).filter { $0.category == .overdue }
            .max { $0.createdAt < $1.createdAt }
        guard let overdue, case .reminder(let reminderID) = overdue.subject else {
            return DemoStep(
                number: 7, title: "Acknowledgement and completion suppress reminders", details: [],
                checks: [DemoCheck("an overdue notification was recorded at 09:00", false)])
        }
        _ = try await setup.iPad.notificationAction(
            id: overdue.id.rawValue, NotificationActionRequest(action: .acknowledge),
            requestID: "na:\(iPadInstallation):\(overdue.id.rawValue):LISA_ACKNOWLEDGE")
        let deliveries = try host.application.all(Delivery.self).filter {
            $0.payloadKey == "notification:\(overdue.id.rawValue)"
        }
        let iPhoneDelivery = deliveries.first { $0.recipient == .device(DeviceID(setup.iPhoneID)) }
        _ = await host.runtime.runOnce()
        let overdueCaptured = try host.recorder.recent(limit: 500).contains { $0.content.contains(overdue.id.rawValue) }
        let reminder = try host.application.record(Reminder.self, id: reminderID)
        var completed = false
        var openAfterAcknowledgement = false
        if case .task(let taskID) = reminder?.subject {
            let task = try await setup.iPhone.task(id: taskID.rawValue)
            openAfterAcknowledgement = task.status != .completed
            let updated = try await setup.iPhone.updateTask(
                id: taskID.rawValue, TaskPatchRequest(expectedRevision: task.revision, status: .completed),
                requestID: "demo-complete-\(taskID.rawValue)")
            let active = try host.application.all(Reminder.self).filter {
                $0.subject == .task(taskID) && !$0.state.isTerminal
            }
            completed = updated.status == .completed && active.isEmpty
        }
        return DemoStep(
            number: 7, title: "Acknowledgement and completion suppress reminders",
            details: [
                "09:00: overdue notification \(overdue.id.rawValue) recorded for \(deliveries.count) devices",
                "the Demo iPad acknowledged it; the Demo iPhone's pending delivery is \(iPhoneDelivery?.state.rawValue ?? "missing")",
                "the Demo iPhone completed the task; its remaining reminders were cancelled",
            ],
            checks: [
                DemoCheck(
                    "the iPad's acknowledgement suppressed the iPhone's pending delivery",
                    iPhoneDelivery?.state == .suppressed),
                DemoCheck("nothing was sent for the acknowledged notification", !overdueCaptured),
                DemoCheck("acknowledging the reminder did not complete the task", openAfterAcknowledgement),
                DemoCheck("completing the task cancelled its remaining reminders", completed),
            ])
    }

    static func restart(before: Counts, after: Counts, outcome: LisaRuntime.CycleOutcome, notes: [String]) -> DemoStep {
        DemoStep(
            number: 8, title: "Restart without duplicate side effects",
            details: [
                "before: \(before.summary)", "after:  \(after.summary)",
                "recovery: " + (notes.isEmpty ? "nothing to recover" : notes.joined(separator: "; ")),
            ],
            checks: [
                DemoCheck("records are preserved without duplicates", before.records == after.records),
                DemoCheck(
                    "no delivery was repeated",
                    before.deliveries == after.deliveries && before.captures == after.captures),
                DemoCheck("the cycle after the restart completed", outcome.problem == nil),
            ])
    }

    // MARK: - Helpers

    static func injectionTasksUnconfirmed(host: LisaHost) throws -> Bool {
        let foreign = try host.application.all(EmailMessage.self).filter {
            $0.from?.address.hasSuffix("example.net") == true
        }
        let evidence = Set(foreign.map(\.evidenceID))
        let tasks = try host.application.all(LisaTask.self).filter { !evidence.isDisjoint(with: $0.evidenceIDs) }
        return !foreign.isEmpty && tasks.allSatisfy { $0.confirmation != .confirmed }
    }

    static func clockTime(_ date: Date, _ zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Record counts used to show that a restart repeats nothing.
struct Counts: Equatable {
    var emails: Int
    var tasks: Int
    var proposals: Int
    var occurrences: Int
    var news: Int
    var ideas: Int
    var deliveries: Int
    var captures: Int

    init(host: LisaHost) throws {
        let application = host.application
        emails = try application.all(EmailMessage.self).count
        tasks = try application.all(LisaTask.self).count
        proposals = try application.all(EventProposal.self).count
        occurrences = try application.all(CalendarOccurrence.self).count
        news = try application.all(NewsItem.self).count
        ideas = try application.all(Idea.self).count
        deliveries = try application.all(Delivery.self).count
        captures = try host.recorder.recent(limit: 10_000).count
    }

    var records: [Int] { [emails, tasks, proposals, occurrences, news, ideas] }

    var summary: String {
        "\(emails) messages, \(tasks) tasks, \(proposals) proposals, \(occurrences) occurrences, \(news) news, "
            + "\(ideas) idea, \(deliveries) deliveries, \(captures) dry-run captures"
    }
}

extension HostSource {
    var localDirectoryPath: String? {
        if case .localDirectory(let url, _) = access { return url.path }
        return nil
    }
}
