// Acceptance tests for L24, the end-to-end demo (DEMO-01, CLI-01 `lisa demo`; D-39): the offline demonstration runs
// the full synthetic secretary workflow in its own new data directory — ingest and deduplicate, persist, identify the
// event proposals, plan a feasible rundown, produce readable and spoken briefs, capture intended deliveries as dry
// runs for two synthetic devices and the approved address, let an acknowledgement and a completion suppress
// reminders, and restart without duplicate side effects — and every step passes. Independently of the demo's own
// checks, the test then opens the data directory it left, as another restart, and finds that outcome stored, and a
// further cycle repeats nothing. The demo refuses a directory that already holds data, and two runs agree. Everything
// is the bundled synthetic fixtures; no account or network is used and nothing is sent.

import Foundation
import LisaDemo
import LisaDomain
import LisaFixtures
import LisaHost
import LisaSecrets
import LisaTime
import Testing

@Suite("L24 — End-to-end demo", .tags(.acceptance))
struct L24EndToEndDemoTests {
    private let version = "0.0.0-test"

    /// The state of a data directory that a restart must keep and a repeated cycle must not grow.
    private struct Snapshot: Equatable {
        var emails: Int
        var tasks: Int
        var proposals: Int
        var occurrences: Int
        var news: Int
        var ideas: Int
        var reminders: Int
        var notifications: Int
        var deliveries: Int
        var captures: Int

        init(_ host: LisaHost) throws {
            let app = host.application
            emails = try app.all(EmailMessage.self).count
            tasks = try app.all(LisaTask.self).count
            proposals = try app.all(EventProposal.self).count
            occurrences = try app.all(CalendarOccurrence.self).count
            news = try app.all(NewsItem.self).count
            ideas = try app.all(Idea.self).count
            reminders = try app.all(Reminder.self).count
            notifications = try app.all(NotificationIntent.self).count
            deliveries = try app.all(Delivery.self).count
            captures = try host.recorder.recent(limit: 10_000).count
        }
    }

    /// The steps' numbers, titles and checks: what a run shows, without its random identifiers.
    private func outline(_ report: DemoReport) -> [String] {
        report.steps.map { step in
            "\(step.number). \(step.title): "
                + step.checks.map { "\($0.passed ? "ok" : "FAILED") \($0.description)" }.joined(separator: "; ")
        }
    }

    @Test("The demonstration passes every step across its restart, and its data directory holds the outcome")
    func demonstrationPassesAcrossRestart() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("demo")
            let report = try await DemoScenario.run(dataDirectory: directory, applicationVersion: version)
            #expect(report.steps.map(\.number) == Array(1...8))
            for step in report.steps {
                #expect(!step.checks.isEmpty, "step \(step.number) checks nothing")
                let failed = step.checks.filter { !$0.passed }.map(\.description)
                #expect(failed.isEmpty, "step \(step.number), \(step.title): \(failed)")
            }
            #expect(report.passed)
            #expect(report.dataDirectory == directory.path)
            #expect(report.text.contains("All demonstration checks passed."))

            // Open the directory the demo left, as the next start of a host would, one minute after its last cycle.
            let root = try #require(LisaFixtures.root)
            let fixtures = DemoFixtures(root: root)
            let settings = DemoConstants.hostSettings(
                dataDirectory: directory, fixtures: fixtures, applicationVersion: version)
            let clock = ManualWallClock(DemoConstants.start.addingTimeInterval(3_660))
            let host = try LisaHost.open(
                settings: settings,
                platform: HostPlatform(
                    clock: clock, secrets: EnvironmentSecretStore(environment: [:]), mode: "test",
                    network: TestHost.offlineNetwork))
            let app = host.application
            let zone = DemoConstants.zone

            // 1–2. Ingested once and persisted: one message file is a duplicate, and its tasks are stored once.
            let mailFiles = try FileManager.default.contentsOfDirectory(atPath: fixtures.mail.path).filter {
                $0.hasSuffix(".eml")
            }
            #expect(try app.all(EmailMessage.self).count == mailFiles.count - 1)
            let tasks = try app.all(LisaTask.self)
            for title in ["Send the demo slides to Priya", "Draft the demo quarterly summary"] {
                #expect(tasks.filter { $0.title == title }.count == 1, "\(title)")
                #expect(tasks.first { $0.title == title }?.confirmation == .confirmed)
            }
            #expect(try !app.all(CalendarOccurrence.self).isEmpty)
            #expect(try !app.all(NewsItem.self).isEmpty)
            let idea = try String(contentsOf: fixtures.idea, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines)
            #expect(try app.all(Idea.self).map(\.originalCapture) == [idea])
            #expect(try app.all(Preference.self).count == 5)
            #expect(try app.all(DeviceRegistration.self).map(\.deviceClass.rawValue).sorted() == ["iPad", "iPhone"])
            // 3. The forwarded meeting and the invitation are proposals that Lisa did not add to any calendar.
            let proposals = try app.all(EventProposal.self)
            #expect(proposals.contains { $0.title.lowercased().contains("budget review") })
            #expect(proposals.contains { $0.title.lowercased().contains("design review") })
            #expect(proposals.allSatisfy { $0.matchState.name != "matched" })
            // 4. The day's rundown puts no proposed block over a busy event or another block.
            let today = TestTime.date("2026-11-16")
            let plan = try #require(try app.rundown(for: today))
            #expect(StoredPlanCheck.overlaps(in: plan, with: try app.all(CalendarOccurrence.self), zone: zone).isEmpty)
            let held = plan.blocks.filter { $0.kind != .fixedEvent && $0.state != .rejected }
            for block in held {
                #expect(!held.contains { $0.blockID != block.blockID && $0.range.overlaps(block.range) })
            }
            #expect(held.contains { $0.kind == .task })
            // 5. Readable and spoken briefs, the spoken one without links.
            let brief = try #require(try app.brief(for: today))
            #expect(!brief.text.isEmpty)
            #expect(!brief.spokenText.isEmpty)
            #expect(!brief.spokenText.contains("http"))
            #expect(brief.text.contains("Demo unavailable feed"))
            // 6. Every delivery is a dry run, to the approved address, number or paired devices only; the injected
            // recipient got nothing, and the approved addresses are unchanged.
            #expect(try app.all(Delivery.self).allSatisfy { $0.mode == .dryRun })
            let captures = try host.recorder.recent(limit: 10_000)
            #expect(captures.contains { $0.channel == .push })
            for capture in captures {
                switch capture.channel {
                case .email: #expect(capture.recipient == DemoConstants.ownerAddress)
                case .call: #expect(capture.recipient == DemoConstants.ownerPhone)
                case .push: #expect(capture.recipient == "apns development topic \(DemoConstants.appTopic)")
                case .localNotification: Issue.record("the demonstration has no local notification installation")
                }
                #expect(!capture.recipient.contains("example.net"))
                #expect(!capture.recipient.contains("5550177"))
            }
            let effective = try app.services.settings.currentSettings()
            #expect(effective.delivery.approvedEmailAddresses == [DemoConstants.ownerAddress])
            #expect(effective.calls.approvedNumber == DemoConstants.ownerPhone)
            // 7. The acknowledged overdue notification went to no device, and the completed task has no live reminder.
            let overdue = try #require(try app.all(NotificationIntent.self).first { $0.category == .overdue })
            #expect(overdue.state == .resolved)
            let overdueDeliveries = try app.all(Delivery.self).filter { $0.payload == .notification(overdue.id) }
            #expect(overdueDeliveries.count == 2)
            #expect(overdueDeliveries.allSatisfy { $0.state == .suppressed })
            #expect(!captures.contains { $0.content.contains(overdue.id.rawValue) })
            let slides = try #require(tasks.first { $0.title == "Send the demo slides to Priya" })
            #expect(slides.status == .completed)
            let slideReminders = try app.all(Reminder.self).filter { $0.subject == .task(slides.id) }
            #expect(!slideReminders.isEmpty)
            #expect(slideReminders.allSatisfy { $0.state.isTerminal })
            #expect(slideReminders.contains { $0.state.name == "acknowledged" })

            // 8. This restart, and another cycle at the same moment, keep everything and send nothing again.
            let before = try Snapshot(host)
            await host.runtime.runOnce()
            #expect(try Snapshot(host) == before)
            host.close()
        }
    }

    @Test("The demonstration refuses a directory that already holds data, and leaves it as it was")
    func demonstrationRefusesExistingData() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = try SourceFiles.directory(scratch.path("occupied"))
            let existing = directory.appendingPathComponent("owner-notes.txt")
            try Data("synthetic existing content\n".utf8).write(to: existing)
            await #expect(throws: DemoError.directoryNotEmpty(directory.path)) {
                _ = try await DemoScenario.run(dataDirectory: directory, applicationVersion: version)
            }
            #expect(try scratch.fileNames(in: directory) == ["owner-notes.txt"])
            #expect(try String(contentsOf: existing, encoding: .utf8) == "synthetic existing content\n")
        }
    }

    @Test("Two runs in separate directories reach the same outcome")
    func demonstrationIsRepeatable() async throws {
        try await ScratchDirectory.with { scratch in
            let first = try await DemoScenario.run(dataDirectory: scratch.path("first"), applicationVersion: version)
            let second = try await DemoScenario.run(dataDirectory: scratch.path("second"), applicationVersion: version)
            #expect(first.passed && second.passed)
            #expect(outline(first) == outline(second))
        }
    }
}
