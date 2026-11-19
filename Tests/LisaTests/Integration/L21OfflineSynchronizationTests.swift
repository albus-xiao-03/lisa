// Integration tests for L21, offline synchronization (UI-03, API-03, IDEA-01; D-35, D-45): a companion's queued
// mutations reconcile without duplicates or silent overwrites. A capture whose answer was lost, or whose app was
// stopped while it was in flight, is resent with its original request ID and saved once (the host replays its
// recorded answer); a capture retried after the host's 30-day request record expired still matches the earlier
// capture; captures from two devices that use the same request ID stay separate. A task change queued against a
// revision that is no longer current surfaces as a recoverable 409 conflict with the current revision, leaves the
// newer state untouched and does not stop the rest of the queue; re-queued at the revision the owner reviewed, it is
// applied once. An entry whose retry period has ended fails instead of being resent, and an answer in an unknown API
// version leaves the queue pending until a compatible host replays it. The same holds over loopback.
// The route to the host and the crashing queue storage are test-only substitutes.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L21 — Offline synchronization", .tags(.integration))
struct L21OfflineSynchronizationTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)
    private let minutesPerDay = 24.0 * 60

    private func ideas(_ text: String, in host: LisaHost) throws -> [Idea] {
        try host.application.all(Idea.self).filter { $0.originalCapture == text }
    }

    private func idea(_ text: String) -> CaptureRequestDTO {
        CaptureRequestDTO(kind: .idea, text: text, channel: .nativeApp)
    }

    @Test("A capture whose answer was lost is resent with its request ID and saved once")
    func lostAnswerCaptureSavedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.losingAnswers(host.deviceTransport))
            let text = "Organize a synthetic neighborhood book swap"
            let queued = try await phone.queue.submit(
                .capture(idea(text)), using: phone.client, timeLimit: .seconds(10))
            #expect(queued.status == .pending)
            #expect(queued.uncertainSince == start)
            let first = try #require(route.exchanges.last)
            #expect(first.response.status == 201)
            #expect(!APIExchange.isReplay(first.response))
            #expect(try ideas(text, in: host).count == 1)

            testHost.advance(minutes: 5)
            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [queued.id])
            let retry = try #require(route.exchanges.last)
            #expect(retry.request.header("Lisa-Request-ID") == queued.requestID)
            #expect(retry.response.status == 201)
            #expect(APIExchange.isReplay(retry.response))
            #expect(retry.response.body == first.response.body)
            #expect(try ideas(text, in: host).count == 1)
            #expect(try host.application.all(Capture.self).count == 1)
            let done = try #require(await phone.queue.entry(queued.id))
            #expect(done.status == .done)
            #expect(done.attempts == 2)
            host.close()
        }
    }

    @Test("A capture in flight when the app was stopped is recovered as uncertain, resent with its ID and saved once")
    func captureInFlightWhenAppStoppedSavedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            // The app sends a capture; the host applies it, but the app is killed before the answer arrives.
            route.set(.stalledAfterDelivery(host.deviceTransport))
            let storage = CrashableQueueStorage(base: FileQueueStorage(fileURL: phone.queueFile))
            let doomed = try OfflineQueue(storage: storage, clock: { testHost.clock.now() })
            let text = "Map a synthetic cycling route along the river"
            let entry = try await doomed.enqueue(.capture(idea(text)))
            let client = phone.client
            let flushing = Task { await doomed.flush(using: client) }
            #expect(try await route.waitUntilWaiting())
            #expect(try ideas(text, in: host).count == 1)
            storage.crash()
            flushing.cancel()
            _ = await flushing.value

            testHost.advance(minutes: 10)
            try phone.relaunch()
            let recovered = try #require(await phone.queue.entry(entry.id))
            #expect(recovered.status == .pending)
            #expect(recovered.attempts == 1)
            #expect(recovered.uncertainSince == start)
            #expect(recovered.requestID == entry.requestID)

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [entry.id])
            let retry = try #require(route.exchanges.last)
            #expect(retry.request.header("Lisa-Request-ID") == entry.requestID)
            #expect(APIExchange.isReplay(retry.response))
            #expect(try ideas(text, in: host).count == 1)
            #expect(try host.application.all(Capture.self).count == 1)
            host.close()
        }
    }

    @Test("A capture retried after the host's request record expired still matches the earlier capture")
    func captureRetriedAfterLedgerExpiryMatches() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let credential = try #require(try phone.credential())
            let text = "Write a synthetic family recipe booklet"
            let request = APIExchange.request(
                .capture, body: try APIExchange.json(idea(text)), requestID: "l21-capture-retry-0001",
                credential: credential)

            let first = try await host.deviceTransport.send(request)
            #expect(first.status == 201)
            let original = try APIExchange.decode(CaptureDTO.self, first)
            #expect(original.created)

            // Within the 30-day retention, a retry replays the recorded answer.
            testHost.advance(minutes: 29 * minutesPerDay)
            let replay = try await host.deviceTransport.send(request)
            #expect(replay.status == 201)
            #expect(APIExchange.isReplay(replay))
            #expect(replay.body == first.body)

            // After it, the capture's own request ID still matches: 200 with the earlier capture, not a new one.
            testHost.advance(minutes: 2 * minutesPerDay)
            let late = try await host.deviceTransport.send(request)
            #expect(late.status == 200)
            #expect(!APIExchange.isReplay(late))
            let matched = try APIExchange.decode(CaptureDTO.self, late)
            #expect(!matched.created)
            #expect(matched.id == original.id)
            #expect(matched.ideaID == original.ideaID)
            #expect(try ideas(text, in: host).count == 1)
            #expect(try host.application.all(Capture.self).count == 1)
            host.close()
        }
    }

    @Test("Captures from two devices that use the same request ID are both saved")
    func requestIDsArePerDevice() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            try await pad.pair(codeFrom: owner)

            // The ledger keys requests by caller and request ID (D-35), so the same ID from another device is a new
            // request, not a retry of the first device's capture.
            let shared = "synthetic-shared-request-id-0001"
            let fromPhone = try await phone.client.capture(idea("Phone: grow synthetic tomatoes"), requestID: shared)
            let fromPad = try await pad.client.capture(idea("Pad: repaint the synthetic shed"), requestID: shared)
            #expect(fromPhone.created)
            #expect(fromPad.created)
            #expect(fromPad.id != fromPhone.id)
            #expect(try ideas("Phone: grow synthetic tomatoes", in: host).count == 1)
            #expect(try ideas("Pad: repaint the synthetic shed", in: host).count == 1)
            host.close()
        }
    }

    @Test(
        "A task change queued against an old revision surfaces a recoverable conflict and never overwrites the newer state"
    )
    func staleTaskChangeSurfacesConflict() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = OwnerClient.inProcess(host)
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            let title = "Renew the synthetic library card"
            let task = try await owner.createTask(TaskCreateRequest(title: title))
            let seen = try await phone.client.task(id: task.id)

            // Offline, the phone renames the task and captures an idea.
            route.set(.unreachable)
            let renamed = "Renew the synthetic library card online"
            let change = try await phone.queue.submit(
                .updateTask(id: task.id, TaskPatchRequest(expectedRevision: seen.revision, title: renamed)),
                using: phone.client, timeLimit: .seconds(5))
            let note = "Ask the synthetic library about the reading club"
            let capture = try await phone.queue.submit(
                .capture(idea(note)), using: phone.client, timeLimit: .seconds(5))
            #expect(await phone.queue.pendingEntries.map(\.id) == [change.id, capture.id])

            // Meanwhile the owner changes the task on the host.
            let newer = try await owner.updateTask(
                id: task.id, TaskPatchRequest(expectedRevision: seen.revision, priority: .high))
            #expect(newer.revision != seen.revision)

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.conflicts == [change.id])
            #expect(report.applied == [capture.id])
            #expect(report.stop == .finished)
            let conflict = try #require(await phone.queue.entry(change.id))
            #expect(conflict.status == .conflict)
            #expect(conflict.lastError?.status == 409)
            #expect(conflict.lastError?.code == .conflict)
            #expect(conflict.serverRevision == newer.revision)
            #expect(await phone.queue.conflictEntries.map(\.id) == [change.id])
            #expect(await phone.queue.pendingEntries.isEmpty)
            let untouched = try await owner.task(id: task.id)
            #expect(untouched.title == title)
            #expect(untouched.priority == .high)
            #expect(untouched.revision == newer.revision)
            #expect(try ideas(note, in: host).count == 1)

            // The owner reviews the current task and re-queues the change at the revision they saw.
            let requeued = try await phone.queue.requeue(change.id, expectedRevision: conflict.serverRevision)
            #expect(requeued.status == .pending)
            #expect(requeued.requestID != change.requestID)
            let second = await phone.queue.flush(using: phone.client)
            #expect(second.applied == [change.id])
            let applied = try await owner.task(id: task.id)
            #expect(applied.title == renamed)
            #expect(applied.priority == .high)
            #expect(await phone.queue.conflictEntries.isEmpty)
            host.close()
        }
    }

    @Test("An entry that may have been applied longer ago than the retry period fails instead of being resent")
    func entryPastRetryPeriodFails() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.losingAnswers(host.deviceTransport))
            let text = "Start a synthetic houseplant journal"
            let queued = try await phone.queue.submit(
                .capture(idea(text)), using: phone.client, timeLimit: .seconds(10))
            #expect(queued.uncertainSince == start)
            #expect(try ideas(text, in: host).count == 1)

            // The phone stays away for longer than the host remembers request IDs.
            route.set(.unreachable)
            testHost.advance(minutes: 30 * minutesPerDay + 1)
            route.set(.connected(host.deviceTransport))
            let exchanged = route.exchanges.count
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.failed == [queued.id])
            #expect(report.applied.isEmpty)
            #expect(route.exchanges.count == exchanged)
            let failed = try #require(await phone.queue.entry(queued.id))
            #expect(failed.status == .failed)
            #expect(failed.lastError?.message.contains("retry period has ended") == true)
            #expect(await phone.queue.failedEntries.map(\.id) == [queued.id])
            #expect(try ideas(text, in: host).count == 1)
            host.close()
        }
    }

    @Test("An answer in an unknown API version leaves the queue pending; a compatible host then replays it")
    func unknownAPIVersionLeavesEntriesPending() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.unreachable)
            let firstText = "Draw a synthetic map of the allotment"
            let secondText = "Price a synthetic rain barrel"
            let first = try await phone.queue.submit(
                .capture(idea(firstText)), using: phone.client, timeLimit: .seconds(5))
            let second = try await phone.queue.submit(
                .capture(idea(secondText)), using: phone.client, timeLimit: .seconds(5))

            // The host answers, but in a major version the client does not speak: nothing counts as done, the
            // answered entry may have been applied, and the flush stops.
            route.set(.reportingVersion(host.deviceTransport, "2.0"))
            let exchanged = route.exchanges.count
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied.isEmpty)
            #expect(report.stop == .stopped(.incompatibleVersion("2.0")))
            #expect(route.exchanges.count == exchanged + 1)
            #expect(await phone.queue.pendingEntries.map(\.id) == [first.id, second.id])
            #expect(await phone.queue.entry(first.id)?.uncertainSince != nil)

            route.set(.connected(host.deviceTransport))
            let resumed = await phone.queue.flush(using: phone.client)
            #expect(resumed.applied == [first.id, second.id])
            #expect(route.exchanges.dropFirst(exchanged + 1).first.map { APIExchange.isReplay($0.response) } == true)
            #expect(try ideas(firstText, in: host).count == 1)
            #expect(try ideas(secondText, in: host).count == 1)
            host.close()
        }
    }

    @Test("Over loopback, queued changes reconcile after the host restarts: one capture and a recoverable conflict")
    func offlineChangesReconcileOverLoopback() async throws {
        try await ScratchDirectory.with { scratch in
            var testHost = TestHost(scratch: scratch, now: start)
            testHost.settings.api = LoopbackAPIServer.settings()
            var host = try testHost.open()
            var server = try await LoopbackAPIServer.start(for: host)
            let transport = try server.deviceTransport()
            defer { transport.invalidate() }
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: transport, clock: testHost.clock)
            try await phone.pair(codeFrom: server.ownerClient())
            let owner = try server.ownerClient()
            let task = try await owner.createTask(TaskCreateRequest(title: "Book the synthetic dentist visit"))
            let seen = try await phone.client.task(id: task.id)
            let newer = try await owner.updateTask(
                id: task.id, TaskPatchRequest(expectedRevision: seen.revision, notes: "Synthetic: mornings only"))

            // The host stops; the phone, which still holds the old revision, queues a change and a capture.
            await server.stop()
            host.close()
            let change = try await phone.queue.submit(
                .updateTask(id: task.id, TaskPatchRequest(expectedRevision: seen.revision, status: .completed)),
                using: phone.client, timeLimit: .seconds(20))
            let text = "Collect synthetic seashells for a mobile"
            let capture = try await phone.queue.submit(
                .capture(idea(text)), using: phone.client, timeLimit: .seconds(20))
            #expect(await phone.queue.pendingEntries.map(\.id) == [change.id, capture.id])

            testHost.settings.api = LoopbackAPIServer.settings(port: server.devicePort)
            host = try testHost.open()
            server = try await LoopbackAPIServer.start(for: host)
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.conflicts == [change.id])
            #expect(report.applied == [capture.id])
            #expect(await phone.queue.entry(change.id)?.serverRevision == newer.revision)
            let current = try await OwnerClient.inProcess(host).task(id: task.id)
            #expect(current.status == .open)
            #expect(current.notes == "Synthetic: mornings only")

            // Retrying the capture with its request ID returns the recorded answer; nothing is captured twice.
            let retried = try await phone.client.capture(idea(text), requestID: capture.requestID)
            let first = try #require(try await phone.queue.entry(capture.id)?.decodedResponse(as: CaptureDTO.self))
            #expect(retried == first)
            #expect(try ideas(text, in: host).count == 1)
            await server.stop()
            host.close()
        }
    }
}
