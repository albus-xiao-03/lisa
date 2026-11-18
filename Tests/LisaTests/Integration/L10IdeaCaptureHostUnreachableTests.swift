// Integration tests for L10, idea capture while the host cannot be reached (IDEA-01, UI-03, API-03, NOTIFY-07; D-35,
// D-44, D-45): a companion's capture made while the host is unreachable, or too slow to answer within the submission
// time limit, persists in the app's durable queue (an owner-only file kept across a relaunch) and shows as pending;
// after reconnection it arrives once and verbatim, and later flushes and relaunches send nothing again. The same holds
// over loopback, with the real network server and the companions' URLSession transport, while the host is stopped and
// after it restarts. The route to the host is a test-only substitute in process. (Model unavailable is L10's T2 part.)

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L10 — Idea capture, host unreachable", .tags(.integration))
struct L10IdeaCaptureHostUnreachableTests {
    private let start = TestTime.instant("2026-11-16T07:00", in: TestTime.newYork)

    /// The host's ideas whose original capture is `text`.
    private func ideas(_ text: String, in host: LisaHost) throws -> [Idea] {
        try host.application.all(Idea.self).filter { $0.originalCapture == text }
    }

    private func idea(_ text: String) -> CaptureRequestDTO {
        CaptureRequestDTO(kind: .idea, text: text, channel: .nativeApp)
    }

    @Test("A capture made while the host cannot be reached persists on the client and arrives once after reconnection")
    func captureWhileHostUnreachable() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            let deviceID = try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.unreachable)
            let original = "Sketch a synthetic herb garden for the balcony, maybe with a drip line"
            let queued = try await phone.queue.submit(
                .capture(idea(original)), using: phone.client, timeLimit: .seconds(10))
            #expect(queued.status == .pending)
            #expect(queued.attempts == 1)
            #expect(queued.uncertainSince == nil)
            #expect(queued.lastError?.message.contains("could not be reached") == true)
            #expect(await phone.queue.pendingEntries.map(\.id) == [queued.id])
            #expect(try host.application.all(Capture.self).isEmpty)
            #expect(try ideas(original, in: host).isEmpty)

            // The capture waits in an owner-only file and survives a relaunch of the app unchanged.
            let attributes = try FileManager.default.attributesOfItem(atPath: phone.queueFile.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            try phone.relaunch()
            let kept = try #require(await phone.queue.entry(queued.id))
            #expect(kept.status == .pending)
            #expect(kept.requestID == queued.requestID)
            #expect(try kept.mutation() == .capture(idea(original)))

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [queued.id])
            #expect(report.stop == .finished)
            #expect(report.remaining == 0)
            let stored = try ideas(original, in: host)
            #expect(stored.count == 1)
            #expect(stored.first?.lifecycle == .inbox)
            let captures = try host.application.all(Capture.self)
            #expect(captures.count == 1)
            #expect(captures.first?.channel == .nativeApp)
            #expect(captures.first?.principal == .pairedDevice(DeviceID(deviceID)))
            #expect(captures.first?.requestID == queued.requestID)
            let done = try #require(await phone.queue.entry(queued.id))
            #expect(done.status == .done)
            let answer = try #require(try done.decodedResponse(as: CaptureDTO.self))
            #expect(answer.created)
            #expect(answer.ideaID == stored.first?.id.rawValue)
            #expect(await phone.queue.pendingEntries.isEmpty)

            // Later flushes and relaunches send nothing again.
            let exchanged = route.exchanges.count
            _ = await phone.queue.flush(using: phone.client)
            try phone.relaunch()
            _ = await phone.queue.flush(using: phone.client)
            #expect(route.exchanges.count == exchanged)
            #expect(try ideas(original, in: host).count == 1)
            host.close()
        }
    }

    @Test("A capture made while the host is too slow to answer in time stays pending and arrives once")
    func captureWhileHostTooSlow() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.stalled)
            let original = "Try a synthetic sourdough schedule that fits workdays"
            let exchanged = route.exchanges.count
            let began = ContinuousClock.now
            let queued = try await phone.queue.submit(
                .capture(idea(original)), using: phone.client, timeLimit: .milliseconds(200))
            #expect(ContinuousClock.now - began < .seconds(30))
            #expect(queued.status == .pending)
            // The client cannot know whether the request arrived, so it keeps it for a retry with the same ID.
            #expect(queued.uncertainSince != nil)
            #expect(route.exchanges.count == exchanged)
            #expect(try ideas(original, in: host).isEmpty)

            route.set(.connected(host.deviceTransport))
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [queued.id])
            #expect(try ideas(original, in: host).count == 1)
            #expect(route.exchanges.last?.request.header("Lisa-Request-ID") == queued.requestID)
            host.close()
        }
    }

    @Test("Several captures queued while the host is unreachable arrive in queue order, each once")
    func severalCapturesArriveInOrder() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: route, clock: testHost.clock)
            try await pad.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.unreachable)
            let first = "Plan a synthetic weekend hike with a picnic stop"
            let second = "Learn three synthetic chess openings"
            let link = CaptureRequestDTO(
                kind: .link, url: "https://example.com/synthetic-article", title: "A synthetic article",
                channel: .nativeApp)
            var queued: [QueuedRequest] = []
            for capture in [idea(first), link, idea(second)] {
                queued.append(try await pad.queue.submit(.capture(capture), using: pad.client, timeLimit: .seconds(5)))
                testHost.advance(minutes: 1)
            }
            #expect(queued.allSatisfy { $0.status == .pending })
            #expect(await pad.queue.pendingEntries.map(\.id) == queued.map(\.id))

            route.set(.connected(host.deviceTransport))
            let exchanged = route.exchanges.count
            let report = await pad.queue.flush(using: pad.client)
            #expect(report.applied == queued.map(\.id))
            #expect(
                route.exchanges.dropFirst(exchanged).map { $0.request.header("Lisa-Request-ID") }
                    == queued.map { $0.requestID as String? })
            #expect(try ideas(first, in: host).count == 1)
            #expect(try ideas(second, in: host).count == 1)
            let captures = try host.application.all(Capture.self)
            #expect(captures.count == 3)
            #expect(captures.filter { $0.kind == .link }.map(\.url) == ["https://example.com/synthetic-article"])
            host.close()
        }
    }

    @Test(
        "Over loopback, a capture made while the host is stopped persists on the client and arrives once after the host restarts"
    )
    func captureWhileHostStoppedOverLoopback() async throws {
        try await ScratchDirectory.with { scratch in
            var testHost = TestHost(scratch: scratch, now: start)
            testHost.settings.api = LoopbackAPIServer.settings()
            var host = try testHost.open()
            var server = try await LoopbackAPIServer.start(for: host)
            let transport = try server.deviceTransport()
            defer { transport.invalidate() }
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: transport, clock: testHost.clock)
            try await phone.pair(codeFrom: server.ownerClient())

            // The host stops: the server closes and nothing listens on the device port any more.
            await server.stop()
            host.close()
            let original = "Build a synthetic bird feeder from scrap wood"
            let queued = try await phone.queue.submit(
                .capture(idea(original)), using: phone.client, timeLimit: .seconds(20))
            #expect(queued.status == .pending)
            #expect(queued.lastError != nil)
            try phone.relaunch()
            #expect(await phone.queue.pendingEntries.map(\.id) == [queued.id])

            // The host restarts at the same address and the queue is flushed.
            testHost.settings.api = LoopbackAPIServer.settings(port: server.devicePort)
            host = try testHost.open()
            server = try await LoopbackAPIServer.start(for: host)
            #expect(try ideas(original, in: host).isEmpty)
            let report = await phone.queue.flush(using: phone.client)
            #expect(report.applied == [queued.id])
            #expect(report.remaining == 0)
            #expect(try ideas(original, in: host).count == 1)
            #expect(try host.application.all(Capture.self).map(\.requestID) == [queued.requestID])
            _ = await phone.queue.flush(using: phone.client)
            #expect(try ideas(original, in: host).count == 1)
            await server.stop()
            host.close()
        }
    }
}
