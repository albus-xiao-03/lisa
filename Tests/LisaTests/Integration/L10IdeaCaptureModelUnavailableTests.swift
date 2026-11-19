// Integration tests for L10, idea capture while the model is unavailable (IDEA-01, MODEL-04, MAIL-02; D-31, D-33,
// D-36): with no model configured, an idea is saved verbatim at once and stays usable (edited, planned, retried
// without duplication) across a restart; email that needs interpretation waits as "awaiting model" instead of being
// guessed while calendars, confirmed tasks, planning, reminders and the template brief go on; once a scripted model
// answers after an outage and a timeout, the waiting email is extracted. (Host unreachable is L10's T3 part.)

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaInference
import LisaOwnerData
import LisaTime
import Testing

@Suite("L10 — Idea capture, model unavailable", .tags(.integration))
struct L10IdeaCaptureModelUnavailableTests {
    private let start = TestTime.instant("2026-11-16T07:00", in: TestTime.newYork)
    private let today = TestTime.date("2026-11-16")

    @Test("With no model configured, an idea is saved verbatim at once and stays usable across a restart")
    func ideaSavedAndUsableWithoutAModel() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            #expect(testHost.settings.model == ModelChoice.none)
            var host = try testHost.open()
            let original = "Prototype a synthetic reading lamp, maybe with a dimmer"
            let request = CaptureRequest(kind: .idea, text: original, channel: .nativeApp, requestID: "l10-idea-1")
            let result = try host.application.capture(request, by: .localOwner)
            #expect(result.created)
            let idea = try #require(result.idea)
            #expect(idea.originalCapture == original)
            #expect(idea.lifecycle == .inbox)
            #expect(result.capture.processing != .awaitingModel)

            let edited = try host.application.editIdea(
                idea.id, expectedRevision: idea.revision,
                IdeaEdit(
                    tags: ["home"], notes: "Synthetic notes", priority: .high, estimatedMinutes: 45,
                    deadline: .onDate(TestTime.date("2026-11-20"))),
                by: .localOwner)
            _ = try host.application.moveIdea(
                idea.id, to: .availableForPlanning, expectedRevision: edited.revision, by: .localOwner)
            // Deterministic planning needs no model: the idea gets an exploration block today.
            let plan = try #require(try host.application.rundown(for: today))
            #expect(plan.blocks.contains { $0.subject == .idea(idea.id) && $0.kind == .idea })

            try testHost.restart(&host)
            await host.runtime.runOnce()
            let stored = try #require(try host.application.record(Idea.self, id: idea.id))
            #expect(stored.originalCapture == original)
            #expect(stored.tags == ["home"])
            #expect(stored.notes == "Synthetic notes")
            #expect(stored.priority == .high)
            #expect(stored.estimatedMinutes == 45)
            #expect(stored.deadline == .onDate(TestTime.date("2026-11-20")))
            let replanned = try #require(try host.application.rundown(for: today))
            #expect(replanned.blocks.contains { $0.subject == .idea(idea.id) })
            let retried = try host.application.capture(request, by: .localOwner)
            #expect(!retried.created)
            #expect(retried.idea?.id == idea.id)
            #expect(try host.application.all(Idea.self).count == 1)
            host.close()
        }
    }

    @Test(
        "Email waits for a model instead of being guessed; the rest goes on, and it is extracted once a model answers")
    func emailWaitsForAModel() async throws {
        try await ScratchDirectory.with { scratch in
            let mailbox = scratch.path("mailbox")
            let calendar = scratch.path("calendars", "work.ics")
            let body = "Task: Return the synthetic library books\nDue: 2026-11-18 12:00\n"
            try SourceFiles.write(
                SyntheticMail.message(
                    subject: "Books", from: "Library <library@example.com>", to: TestHost.ownerAddress,
                    messageID: "<l10-1@example.com>", body: body),
                named: "m001", in: mailbox, receivedAt: start.addingTimeInterval(-600))
            try SourceFiles.write(
                SyntheticEvent.calendar([
                    SyntheticEvent(
                        uid: "l10-standup@example.com", title: "Synthetic standup", start: "2026-11-16T09:00",
                        end: "2026-11-16T09:30")
                ]), to: calendar, modifiedAt: start)
            let testHost = TestHost(
                scratch: scratch, now: start,
                sources: [SourceFiles.mailSource(mailbox), SourceFiles.calendarSource(calendar)])
            var host = try testHost.open()
            let manual = try host.application.createTask(
                TaskDraft(
                    title: "Synthetic dentist appointment", priority: .high,
                    deadline: SyntheticTask.due(TestTime.instant("2026-11-17T15:00", in: TestTime.newYork)),
                    estimatedMinutes: 30),
                by: .localOwner)
            await host.runtime.runOnce()

            let email = try #require(try host.application.all(EmailMessage.self).first)
            #expect(email.extraction == .awaitingModel)
            #expect(try host.application.all(LisaTask.self).map(\.id) == [manual.id])
            let waiting = try host.application.all(AuditEvent.self).filter { $0.action == "review.extraction" }
            #expect(waiting.allSatisfy { $0.outcome == .skipped && $0.detail.contains("awaiting model") })
            #expect(!waiting.isEmpty)
            // Calendars, confirmed tasks, planning, reminders and the template brief continue without a model.
            #expect(try host.application.all(CalendarOccurrence.self).count == 1)
            #expect(try host.application.all(Reminder.self).contains { $0.subject == .task(manual.id) })
            #expect(
                try host.application.rundown(for: today)?.blocks.contains { $0.subject == .task(manual.id) } == true)
            let brief = try #require(try host.application.brief(for: today))
            #expect(brief.templateOnly)

            let model = ScriptedModelProvider(steps: [
                .fail(.unavailable("synthetic outage")), .fail(.timeout),
                .respond(
                    ModelReplies.items(
                        ModelExtractedItem(
                            kind: "commitment", title: "Return the synthetic library books", confirmation: "possible",
                            deadline: "2026-11-18 12:00", evidence: "Task: Return the synthetic library books",
                            addressedToOwner: true))),
            ])
            try await ScriptedReview.run(host, provider: model)
            #expect(try host.application.record(EmailMessage.self, id: email.id)?.extraction == .awaitingModel)
            try testHost.restart(&host)
            try await ScriptedReview.run(host, provider: model)
            #expect(try host.application.record(EmailMessage.self, id: email.id)?.extraction == .awaitingModel)
            try await ScriptedReview.run(host, provider: model)
            #expect(try host.application.record(EmailMessage.self, id: email.id)?.extraction == .extracted)
            let extracted = try host.application.all(LisaTask.self).filter { $0.origin == .extracted }
            #expect(extracted.map(\.title) == ["Return the synthetic library books"])
            #expect(extracted.first?.confirmation == .possible)
            #expect(model.requestCount == 3)
            let succeeded = try host.application.all(AuditEvent.self).filter {
                $0.action == "review.extraction" && $0.outcome == .succeeded
            }
            #expect(succeeded.map { $0.detail.hasPrefix("provider=scripted-test-model") } == [true])
            host.close()
        }
    }
}
