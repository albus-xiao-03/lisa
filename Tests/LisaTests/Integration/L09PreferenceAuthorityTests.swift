// Integration tests for L09, preference authority (MEM-01, DATA-04, MODEL-03; D-30, D-33): explicit preferences
// survive model inference and restarts; an inferred preference takes effect only once the owner confirms it and is
// never replaced by a later inference; owner corrections to a task extracted from a message survive reprocessing of
// that message by a scripted model, without duplicating the task.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaInference
import LisaOwnerData
import LisaTime
import Testing

@Suite("L09 — Preference authority", .tags(.integration))
struct L09PreferenceAuthorityTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)
    private let request = "Please submit the synthetic report by 2026-11-20."

    @Test("An explicit preference survives model inference and a restart, and stays in effect")
    func explicitPreferenceSurvivesInference() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            var host = try testHost.open()
            let preferences = host.application.services.preferences
            _ = try host.application.setPreference(.bufferMinutes, .number(15), expectedRevision: nil, by: .localOwner)
            #expect(try preferences.infer(.bufferMinutes, .number(0), evidence: []) == nil)

            try testHost.restart(&host)
            #expect(try host.application.services.preferences.infer(.bufferMinutes, .number(5), evidence: []) == nil)
            let stored = try host.application.services.preferences.list()
            #expect(stored.map(\.key) == [.bufferMinutes])
            #expect(stored.first?.origin == .explicit)
            #expect(stored.first?.value == .number(15))
            #expect(try host.application.services.settings.currentSettings().planning.bufferMinutes == 15)
            host.close()
        }
    }

    @Test("An inferred preference takes effect only once confirmed, and a later inference never replaces it")
    func inferredPreferenceNeedsConfirmation() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            var host = try testHost.open()
            let defaultTime = BriefSettings().deliveryTime
            let inferred = try host.application.services.preferences.infer(.briefTime, .text("07:15"), evidence: [])
            #expect(inferred?.origin == .inferred)
            #expect(inferred?.isEffective == false)
            #expect(try host.application.services.settings.currentSettings().brief.deliveryTime == defaultTime)

            try testHost.restart(&host)
            #expect(try host.application.services.settings.currentSettings().brief.deliveryTime == defaultTime)
            _ = try host.application.confirmPreference(.briefTime, by: .localOwner)
            #expect(try host.application.services.preferences.infer(.briefTime, .text("05:00"), evidence: []) == nil)
            #expect(
                try host.application.services.settings.currentSettings().brief.deliveryTime == TestTime.time("07:15"))

            // An explicit value replaces the inferred one, and inference cannot take it back.
            _ = try host.application.setPreference(.briefTime, .text("06:45"), expectedRevision: nil, by: .localOwner)
            #expect(try host.application.services.preferences.infer(.briefTime, .text("05:00"), evidence: []) == nil)
            try testHost.restart(&host)
            let stored = try #require(try host.application.services.preferences.list().first)
            #expect(stored.origin == .explicit)
            #expect(
                try host.application.services.settings.currentSettings().brief.deliveryTime == TestTime.time("06:45"))
            host.close()
        }
    }

    /// A host with one message asking the owner to submit a report, before any review.
    private func hostWithRequest(_ scratch: ScratchDirectory) async throws -> (TestHost, LisaHost) {
        let mailbox = scratch.path("mailbox")
        try SourceFiles.write(
            SyntheticMail.message(
                subject: "Report", from: "Colleague <colleague@example.com>", to: TestHost.ownerAddress,
                messageID: "<l09-1@example.com>", body: request + "\n"),
            named: "m001", in: mailbox, receivedAt: start.addingTimeInterval(-600))
        let testHost = TestHost(scratch: scratch, now: start, sources: [SourceFiles.mailSource(mailbox)])
        let host = try testHost.open()
        await host.runtime.runOnce()
        return (testHost, host)
    }

    /// What a model says about the message: one commitment with the given details, quoting the message.
    private func reply(
        title: String = "Submit the synthetic report", deadline: String, priority: String, minutes: Int
    ) -> ScriptedModelProvider.Step {
        .respond(
            ModelReplies.items(
                ModelExtractedItem(
                    kind: "commitment", title: title, confirmation: "possible", deadline: deadline,
                    durationMinutes: minutes, priority: priority, evidence: request, addressedToOwner: true)))
    }

    /// Queues the stored message for extraction again, as reprocessing the same source does. R1 has no command that
    /// re-extracts a reviewed message, so the test re-queues it through the store.
    private func requeue(_ host: LisaHost) throws {
        try host.storage.records.write { tx in
            for var email in try tx.find(EmailMessage.self, .all) {
                email.extraction = .pending
                try tx.update(email)
            }
        }
    }

    @Test("Owner corrections to an extracted task survive reprocessing of its message, without a duplicate task")
    func correctionsSurviveReprocessing() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, opened) = try await hostWithRequest(scratch)
            var host = opened
            let model = ScriptedModelProvider(steps: [
                reply(deadline: "2026-11-20 17:00", priority: "normal", minutes: 30),
                reply(deadline: "2026-11-21 09:00", priority: "low", minutes: 45),
            ])
            try await ScriptedReview.run(host, provider: model)
            let extracted = try #require(try host.application.all(LisaTask.self).first)
            #expect(extracted.origin == .extracted)
            let correctedDeadline = SyntheticTask.due(TestTime.instant("2026-11-19T12:00", in: TestTime.newYork))
            _ = try host.application.correctTask(
                extracted.id, expectedRevision: extracted.revision,
                TaskCorrection(priority: .high, deadline: correctedDeadline, confirmation: .confirmed),
                by: .localOwner)

            try requeue(host)
            try await ScriptedReview.run(host, provider: model)
            try testHost.restart(&host)
            let tasks = try host.application.all(LisaTask.self)
            #expect(tasks.count == 1)
            let task = try #require(tasks.first)
            #expect(task.id == extracted.id)
            #expect(task.deadline == correctedDeadline)
            #expect(task.priority == .high)
            #expect(task.confirmation == .confirmed)
            #expect(task.ownerCorrected == [.deadline, .priority, .confirmation])
            // A field the owner did not correct follows the newer suggestion.
            #expect(task.estimatedMinutes == 45)
            #expect(model.requestCount == 2)
            host.close()
        }
    }

    @Test("A renamed extracted task is not duplicated when its message is reprocessed")
    func renamedTaskIsNotDuplicated() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host) = try await hostWithRequest(scratch)
            let model = ScriptedModelProvider(steps: [
                reply(deadline: "2026-11-20 17:00", priority: "normal", minutes: 30),
                reply(deadline: "2026-11-20 17:00", priority: "normal", minutes: 30),
            ])
            try await ScriptedReview.run(host, provider: model)
            let extracted = try #require(try host.application.all(LisaTask.self).first)
            _ = try host.application.correctTask(
                extracted.id, expectedRevision: extracted.revision,
                TaskCorrection(title: "Submit the final synthetic report"), by: .localOwner)

            try requeue(host)
            try await ScriptedReview.run(host, provider: model)
            let tasks = try host.application.all(LisaTask.self)
            #expect(tasks.map(\.title) == ["Submit the final synthetic report"], "tasks: \(tasks.map(\.title))")
            host.close()
        }
    }
}
