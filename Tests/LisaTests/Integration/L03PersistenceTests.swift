// Integration tests for L03, persistence across a restart (DATA-02, IDEA-01, MEM-01, INGEST-01, REM-01, OPS-01;
// D-22, D-30, D-31, D-32, D-36): tasks, ideas with their original capture, explicit and inferred preferences, source
// cursors and schedules, and acknowledgements survive closing the host and opening its data directory again.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("L03 — Persistence", .tags(.integration, .recovery))
struct L03PersistenceTests {
    /// Monday 2026-11-16, 08:00 in New York, after quiet hours.
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    @Test("Tasks and ideas survive a restart with their corrections, lifecycle and original capture")
    func tasksAndIdeasSurvive() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            var host = try testHost.open()
            let app = host.application
            let due = SyntheticTask.due(TestTime.instant("2026-11-18T17:00", in: TestTime.newYork))
            let report = try app.createTask(
                TaskDraft(title: "Send the synthetic report", deadline: due, estimatedMinutes: 45), by: .localOwner)
            let corrected = try app.correctTask(
                report.id, expectedRevision: report.revision, TaskCorrection(priority: .high), by: .localOwner)
            let form = try app.createTask(TaskDraft(title: "Return the synthetic form"), by: .localOwner)
            let done = try app.setTaskStatus(form.id, to: .completed, expectedRevision: form.revision, by: .localOwner)
            let original = "Explore a synthetic garden plan for the spring"
            let request = CaptureRequest(kind: .idea, text: original, channel: .commandLine, requestID: "l03-idea-1")
            let idea = try #require(try app.capture(request, by: .localOwner).idea)
            let edited = try app.editIdea(
                idea.id, expectedRevision: idea.revision,
                IdeaEdit(summary: "Garden plan", tags: ["home"], notes: "Synthetic notes", estimatedMinutes: 40),
                by: .localOwner)
            let moved = try app.moveIdea(
                idea.id, to: .availableForPlanning, expectedRevision: edited.revision, by: .localOwner)

            try testHost.restart(&host)
            let reopened = host.application
            #expect(try reopened.all(LisaTask.self).count == 2)
            let storedReport = try #require(try reopened.record(LisaTask.self, id: report.id))
            #expect(storedReport.title == "Send the synthetic report")
            #expect(storedReport.priority == .high)
            #expect(storedReport.ownerCorrected == [.priority])
            #expect(storedReport.deadline == due)
            #expect(storedReport.estimatedMinutes == 45)
            #expect(storedReport.status == .open)
            #expect(storedReport.revision == corrected.revision)
            let storedForm = try #require(try reopened.record(LisaTask.self, id: form.id))
            #expect(storedForm.status == .completed)
            #expect(storedForm.completedAt == done.completedAt)
            let storedIdea = try #require(try reopened.record(Idea.self, id: idea.id))
            #expect(storedIdea.originalCapture == original)
            #expect(storedIdea.summary == "Garden plan")
            #expect(storedIdea.tags == ["home"])
            #expect(storedIdea.notes == "Synthetic notes")
            #expect(storedIdea.estimatedMinutes == 40)
            #expect(storedIdea.lifecycle == .availableForPlanning)
            #expect(storedIdea.revision == moved.revision)
            // The capture and its request ID are kept too: the same capture retried after the restart adds nothing.
            let retried = try reopened.capture(request, by: .localOwner)
            #expect(!retried.created)
            #expect(retried.idea?.id == idea.id)
            #expect(try reopened.all(Idea.self).count == 1)
            #expect(try reopened.all(Capture.self).count == 1)
            host.close()
        }
    }

    @Test("Explicit and inferred preferences survive a restart, and only effective ones change the settings")
    func preferencesSurvive() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            var host = try testHost.open()
            _ = try host.application.setPreference(.bufferMinutes, .number(10), expectedRevision: nil, by: .localOwner)
            _ = try host.application.setPreference(
                .quietHours, .text("21:30-06:30"), expectedRevision: nil, by: .localOwner)
            let inferred = try host.application.services.preferences.infer(.briefLength, .number(150), evidence: [])
            #expect(inferred?.origin == .inferred)

            try testHost.restart(&host)
            let preferences = try host.application.services.preferences.list()
            #expect(preferences.map(\.key) == [.briefLength, .bufferMinutes, .quietHours])
            #expect(preferences.map(\.origin) == [.inferred, .explicit, .explicit])
            #expect(preferences.map(\.isEffective) == [false, true, true])
            var settings = try host.application.services.settings.currentSettings()
            #expect(settings.planning.bufferMinutes == 10)
            #expect(
                settings.reminders.quietHours == QuietHours(start: TestTime.time("21:30"), end: TestTime.time("06:30")))
            #expect(settings.brief.targetWords == BriefSettings().targetWords)

            _ = try host.application.confirmPreference(.briefLength, by: .localOwner)
            try testHost.restart(&host)
            settings = try host.application.services.settings.currentSettings()
            #expect(settings.brief.targetWords == 150)
            #expect(settings.planning.bufferMinutes == 10)
            host.close()
        }
    }

    @Test("A source's cursor and schedule survive a restart, so no message is read or stored twice")
    func cursorsAndSchedulesSurvive() async throws {
        try await ScratchDirectory.with { scratch in
            let mailbox = scratch.path("mailbox")
            for number in 1...2 {
                try SourceFiles.write(
                    SyntheticMail.message(
                        subject: "Synthetic note \(number)", messageID: "<l03-m00\(number)@example.com>",
                        body: "A synthetic note."),
                    named: "m00\(number)", in: mailbox, receivedAt: start.addingTimeInterval(-3600))
            }
            let testHost = TestHost(scratch: scratch, now: start, sources: [SourceFiles.mailSource(mailbox)])
            var host = try testHost.open()
            let first = await host.runtime.runOnce()
            #expect(first.synchronized.map(\.outcome.inserted) == [2])
            let source = try #require(try host.application.all(Source.self).first { $0.configurationKey == "mailbox" })
            #expect(source.cursor == "m002.eml")

            try testHost.restart(&host)
            // The persisted schedule says the source is not due yet, so the restart alone fetches nothing.
            let early = await host.runtime.runOnce()
            #expect(early.synchronized.isEmpty)
            let kept = try #require(try host.application.record(Source.self, id: source.id))
            #expect(kept.cursor == "m002.eml")
            #expect(kept.lastSuccessAt == source.lastSuccessAt)

            try SourceFiles.write(
                SyntheticMail.message(
                    subject: "Synthetic note 3", messageID: "<l03-m003@example.com>", body: "A synthetic note."),
                named: "m003", in: mailbox, receivedAt: start)
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            let later = await host.runtime.runOnce()
            let sync = try #require(later.synchronized.first)
            // Only the new file was read: the two earlier ones are behind the restored cursor.
            #expect(sync.outcome.inserted == 1)
            #expect(sync.outcome.unchanged == 0)
            #expect(try host.application.all(EmailMessage.self).count == 3)
            #expect(try host.application.record(Source.self, id: source.id)?.cursor == "m003.eml")
            host.close()
        }
    }

    @Test("An acknowledged reminder stays acknowledged after a restart, never fires again and never completes its task")
    func acknowledgementsSurvive() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: start, localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(
                    title: "Call the synthetic office", deadline: SyntheticTask.due(start.addingTimeInterval(90 * 60))),
                by: .localOwner)
            // The one-hour reminder is due at 08:30.
            testHost.advance(minutes: 30)
            await host.runtime.runOnce()
            let presentedForTask = { center.presented.filter { $0.presentation.subjectID == task.id.rawValue }.count }
            // How many reminders fire for one deadline is L15's concern; here only what happens after a restart counts.
            let presentedBeforeRestart = presentedForTask()
            #expect(presentedBeforeRestart >= 1)
            let reminder = try #require(
                try host.application.all(Reminder.self).first {
                    $0.subject == .task(task.id) && $0.occurrenceKey.hasSuffix(":60") && $0.state.name == "delivered"
                })
            let acknowledged = try host.application.actOnReminder(
                .acknowledge, reminder.id, expectedRevision: reminder.revision, by: .localOwner)

            try testHost.restart(&host)
            for _ in 0..<2 {
                testHost.advance(minutes: 20)
                await host.runtime.runOnce()
            }
            let stored = try #require(try host.application.record(Reminder.self, id: reminder.id))
            #expect(stored.state == acknowledged.state)
            #expect(stored.state.name == "acknowledged")
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .open)
            // Nothing that was presented before the restart is presented again after it.
            #expect(presentedForTask() == presentedBeforeRestart)
            let occurrences = try host.application.all(NotificationIntent.self).filter {
                $0.subject == .reminder(reminder.id)
            }
            #expect(occurrences.map(\.state) == [.resolved])
            host.close()
        }
    }
}
