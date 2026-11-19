// Integration tests for L20, revision checks and conflicts (API-03, UI-03, REM-01; D-35, D-47), through the real
// router in process as docs/API.md documents them: a change sent with a revision that is no longer current is a 409
// conflict with `currentRevision` and changes nothing; reloading and resending at the current revision succeeds; a
// successful change answers with the record as stored after the host's follow-up work, so its revision is the one to
// send next. This holds for tasks, ideas, reminders and device notification preferences; a change the record's
// state no longer allows is a 409 as well. Device registrations are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L20 — API revisions and conflicts", .tags(.integration))
struct L20APIConflictTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    private func patch(_ route: APIRoute, _ body: some Encodable, credential: String) throws -> APIRequest {
        APIExchange.request(
            route, body: try APIExchange.json(body), requestID: RequestID.random(), credential: credential)
    }

    @Test("A task change at an old revision is a 409 with the current revision; the answer's revision is the next one")
    func staleTaskRevisionConflicts() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            let credential = try #require(try phone.credential())
            let devices = host.deviceTransport
            let created = try await owner.createTask(
                TaskCreateRequest(
                    title: "Synthetic grant report",
                    deadline: DeadlineDTO(instant: TestTime.instant("2026-11-18T17:00", in: TestTime.newYork))))
            let seen = try await phone.client.task(id: created.id)
            let newer = try await owner.updateTask(
                id: created.id, TaskPatchRequest(expectedRevision: seen.revision, title: "Synthetic grant report v2"))

            let stale = try await devices.send(
                try patch(
                    .updateTask(id: created.id), TaskPatchRequest(expectedRevision: seen.revision, priority: .urgent),
                    credential: credential))
            let conflict = APIExchange.expectError(stale, .conflict)
            #expect(conflict?.currentRevision == newer.revision)
            let unchanged = try await owner.task(id: created.id)
            #expect(unchanged.revision == newer.revision)
            #expect(unchanged.priority == seen.priority)
            #expect(unchanged.title == "Synthetic grant report v2")

            // Reload and resend at the current revision; then keep going with each answer's revision, through changes
            // that make the host replan and recompute reminders.
            let reloaded = try await phone.client.task(id: created.id)
            var current = try await phone.client.updateTask(
                id: created.id, TaskPatchRequest(expectedRevision: reloaded.revision, priority: .urgent))
            #expect(current.priority == .urgent)
            current = try await phone.client.updateTask(
                id: created.id,
                TaskPatchRequest(
                    expectedRevision: current.revision,
                    deadline: DeadlineDTO(instant: TestTime.instant("2026-11-17T12:00", in: TestTime.newYork))))
            current = try await phone.client.updateTask(
                id: created.id, TaskPatchRequest(expectedRevision: current.revision, estimatedMinutes: 90))
            current = try await phone.client.updateTask(
                id: created.id, TaskPatchRequest(expectedRevision: current.revision, status: .completed))
            #expect(current.status == .completed)
            #expect(try await owner.task(id: created.id) == current)
            host.close()
        }
    }

    @Test("An idea change at an old revision is a 409 with the current revision and changes nothing")
    func staleIdeaRevisionConflicts() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            let credential = try #require(try phone.credential())
            let capture = try await owner.capture(
                CaptureRequestDTO(kind: .idea, text: "Build a synthetic rain gauge", channel: .api))
            let idea = try #require(try await owner.ideas().items.first { $0.id == capture.ideaID })

            let moved = try await phone.client.updateIdea(
                id: idea.id, IdeaPatchRequest(expectedRevision: idea.revision, lifecycle: .availableForPlanning))
            #expect(moved.lifecycle == .availableForPlanning)
            let stale = try await host.deviceTransport.send(
                try patch(
                    .updateIdea(id: idea.id), IdeaPatchRequest(expectedRevision: idea.revision, tags: ["garden"]),
                    credential: credential))
            #expect(APIExchange.expectError(stale, .conflict)?.currentRevision == moved.revision)
            let stored = try #require(try host.application.record(Idea.self, id: IdeaID(idea.id)))
            #expect(stored.tags.isEmpty)
            #expect(stored.revision.value == moved.revision)
            #expect(stored.originalCapture == "Build a synthetic rain gauge")
            host.close()
        }
    }

    @Test("A reminder action at an old revision, or one its state no longer allows, is a 409")
    func reminderConflicts() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            let credential = try #require(try phone.credential())
            let task = try await owner.createTask(
                TaskCreateRequest(
                    title: "Synthetic lease signature",
                    deadline: DeadlineDTO(instant: TestTime.instant("2026-11-19T17:00", in: TestTime.newYork))))
            let reminder = try #require(try await phone.client.reminders().items.first { $0.subjectID == task.id })

            let stale = try await host.deviceTransport.send(
                try patch(
                    .reminderAction(id: reminder.id),
                    ReminderActionRequest(action: .snooze, expectedRevision: reminder.revision + 1),
                    credential: credential))
            #expect(APIExchange.expectError(stale, .conflict)?.currentRevision == reminder.revision)
            #expect(try await phone.client.reminders().items.first { $0.id == reminder.id } == reminder)

            let acknowledged = try await phone.client.reminderAction(
                id: reminder.id, ReminderActionRequest(action: .acknowledge, expectedRevision: reminder.revision))
            #expect(acknowledged.state == "acknowledged")
            let again = try await host.deviceTransport.send(
                try patch(
                    .reminderAction(id: reminder.id), ReminderActionRequest(action: .snooze), credential: credential))
            APIExchange.expectError(again, .conflict)
            #expect(
                try host.application.record(Reminder.self, id: ReminderID(reminder.id))?.state.name == "acknowledged")
            host.close()
        }
    }

    @Test("A device preference change at an old revision is a 409 with the current revision")
    func staleDevicePreferencesConflict() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let credential = try #require(try phone.credential())

            let seen = try await phone.client.notificationPreferences()
            let changed = try await phone.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(expectedRevision: seen.revision, showTitles: true))
            #expect(changed.showTitles)
            let stale = try await host.deviceTransport.send(
                try patch(
                    .updateDeviceNotificationPreferences,
                    DeviceNotificationPreferencesPatch(expectedRevision: seen.revision, enabled: false),
                    credential: credential))
            #expect(APIExchange.expectError(stale, .conflict)?.currentRevision == changed.revision)
            let current = try await phone.client.notificationPreferences()
            #expect(current.enabled)
            #expect(current.showTitles)
            #expect(current.revision == changed.revision)
            host.close()
        }
    }
}
