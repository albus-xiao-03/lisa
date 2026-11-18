// Integration tests for L20, request identities and replay (API-03; D-35), through the real router in process as
// docs/API.md documents them: retrying a mutation with the same Lisa-Request-ID returns the recorded response marked
// Lisa-Replayed and applies it once, also when duplicates arrive at the same moment; reusing an ID for a different
// request is a 422; IDs are scoped per caller; definite answers (2xx, 400, 403, 404, 409, 413) are kept for at least
// 30 days, while 401, 429 and 5xx are not, so a retry runs again; pairing responses are never recorded. Device
// registrations are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L20 — API request identities and replay", .tags(.integration))
struct L20APIIdempotencyTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    /// A host with one paired synthetic iPhone, and that phone's credential.
    private func hostWithPhone(_ scratch: ScratchDirectory) async throws -> (TestHost, LisaHost, String) {
        let testHost = TestHost(scratch: scratch, now: start)
        let host = try testHost.open()
        let phone = try SyntheticCompanion(
            "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
        try await phone.pair(codeFrom: OwnerClient.inProcess(host))
        return (testHost, host, try #require(try phone.credential()))
    }

    private func createTask(_ title: String, requestID: String, credential: String?) throws -> APIRequest {
        APIExchange.request(
            .createTask, body: try APIExchange.json(TaskCreateRequest(title: title)), requestID: requestID,
            credential: credential)
    }

    @Test("Retrying a mutation with its request ID replays the recorded answer and applies it once")
    func retryReplaysTheRecordedAnswer() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, credential) = try await hostWithPhone(scratch)
            let devices = host.deviceTransport
            let create = try createTask(
                "Synthetic passport renewal", requestID: "l20-create-0001", credential: credential)
            let first = try await devices.send(create)
            #expect(first.status == 201)
            #expect(!APIExchange.isReplay(first))
            testHost.advance(minutes: 1)
            let second = try await devices.send(create)
            #expect(second.status == 201)
            #expect(APIExchange.isReplay(second))
            #expect(second.body == first.body)
            #expect(try host.application.all(LisaTask.self).count == 1)

            let task = try APIExchange.decode(TaskDTO.self, first)
            let patch = APIExchange.request(
                .updateTask(id: task.id),
                body: try APIExchange.json(TaskPatchRequest(expectedRevision: task.revision, status: .inProgress)),
                requestID: "l20-patch-0001", credential: credential)
            let applied = try await devices.send(patch)
            #expect(applied.status == 200)
            let replayed = try await devices.send(patch)
            #expect(replayed.status == 200)
            #expect(APIExchange.isReplay(replayed))
            #expect(replayed.body == applied.body)
            let stored = try #require(try host.application.record(LisaTask.self, id: TaskID(task.id)))
            #expect(stored.status == .inProgress)
            #expect(stored.revision.value == (try APIExchange.decode(TaskDTO.self, applied)).revision)

            // Within 30 days the answer is still replayed.
            testHost.advance(minutes: 30 * 24 * 60 - 2)
            #expect(APIExchange.isReplay(try await devices.send(create)))
            #expect(try host.application.all(LisaTask.self).count == 1)
            host.close()
        }
    }

    @Test("Reusing a request ID for a different request is a 422 and applies nothing")
    func reusedRequestIDIsRefused() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host, credential) = try await hostWithPhone(scratch)
            let devices = host.deviceTransport
            let shared = "l20-reused-0001"
            #expect(
                try await devices.send(createTask("Synthetic tax form", requestID: shared, credential: credential))
                    .status == 201)
            let otherBody = try await devices.send(
                createTask("Another synthetic form", requestID: shared, credential: credential))
            APIExchange.expectError(otherBody, .requestIDReused)
            let otherRoute = APIExchange.request(
                .capture,
                body: try APIExchange.json(CaptureRequestDTO(kind: .idea, text: "Synthetic idea", channel: .api)),
                requestID: shared, credential: credential)
            APIExchange.expectError(try await devices.send(otherRoute), .requestIDReused)
            #expect(try host.application.all(LisaTask.self).map(\.title) == ["Synthetic tax form"])
            #expect(try host.application.all(Capture.self).isEmpty)
            host.close()
        }
    }

    @Test("Request IDs are scoped per caller")
    func requestIDsAreScopedPerCaller() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host, credential) = try await hostWithPhone(scratch)
            let shared = "l20-shared-0001"
            let fromPhone = try await host.deviceTransport.send(
                createTask("Synthetic gym renewal", requestID: shared, credential: credential))
            let fromOwner = try await host.ownerTransport.send(
                createTask("Synthetic gym renewal", requestID: shared, credential: nil))
            #expect(fromPhone.status == 201)
            #expect(fromOwner.status == 201)
            #expect(!APIExchange.isReplay(fromOwner))
            #expect(try host.application.all(LisaTask.self).count == 2)
            host.close()
        }
    }

    @Test("Definite refusals (400, 403, 404, 409) are kept and replayed")
    func definiteRefusalsAreReplayed() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, credential) = try await hostWithPhone(scratch)
            let devices = host.deviceTransport
            let task = try await OwnerClient.inProcess(host).createTask(TaskCreateRequest(title: "Synthetic visa"))
            let refusals: [(APIRequest, APIErrorCode)] = [
                (
                    APIExchange.request(
                        .capture, body: APIExchange.json(text: #"{"kind":"idea","channel":"api"}"#),
                        requestID: "l20-invalid-0001", credential: credential), .invalidRequest
                ),
                (
                    APIExchange.request(
                        .updatePreferences,
                        body: try APIExchange.json(
                            PreferencesPatchRequest(changes: [
                                PreferenceChange(key: "delivery.callsEnabled", value: .flag(true))
                            ])),
                        requestID: "l20-forbidden-01", credential: credential), .forbidden
                ),
                (
                    APIExchange.request(
                        .updateTask(id: TaskID.random().rawValue),
                        body: try APIExchange.json(TaskPatchRequest(expectedRevision: 1, title: "Synthetic")),
                        requestID: "l20-missing-0001", credential: credential), .notFound
                ),
                (
                    APIExchange.request(
                        .updateTask(id: task.id),
                        body: try APIExchange.json(
                            TaskPatchRequest(expectedRevision: task.revision + 5, title: "Synthetic")),
                        requestID: "l20-conflict-0001", credential: credential), .conflict
                ),
            ]
            for (request, code) in refusals {
                let first = try await devices.send(request)
                APIExchange.expectError(first, code)
                #expect(!APIExchange.isReplay(first))
                testHost.advance(minutes: 1)
                let retry = try await devices.send(request)
                APIExchange.expectError(retry, code)
                #expect(APIExchange.isReplay(retry), "\(code)")
                #expect(retry.body == first.body)
            }
            host.close()
        }
    }

    @Test("A 413 is a definite answer that is kept and replayed like the others")
    func payloadTooLargeIsReplayed() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, credential) = try await hostWithPhone(scratch)
            let oversized = Data(
                (#"{"kind":"idea","channel":"api","text":""# + String(repeating: "x", count: 262_144) + #""}"#).utf8)
            let request = APIExchange.request(
                .capture, body: oversized, requestID: "l20-too-large-01", credential: credential)
            let first = try await host.deviceTransport.send(request)
            APIExchange.expectError(first, .payloadTooLarge)
            testHost.advance(minutes: 1)
            let retry = try await host.deviceTransport.send(request)
            APIExchange.expectError(retry, .payloadTooLarge)
            #expect(APIExchange.isReplay(retry))
            host.close()
        }
    }

    @Test("Retryable answers (401, 429, 503) are not kept, so a retry with the same ID runs again")
    func retryableAnswersAreNotKept() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, credential) = try await hostWithPhone(scratch)
            let devices = host.deviceTransport

            // 401: the request is retried with the right credential and applied.
            let wrong = try createTask(
                "Synthetic car service", requestID: "l20-unauth-0001", credential: SyntheticDevice.randomHex(bytes: 32))
            APIExchange.expectError(try await devices.send(wrong), .unauthenticated)
            let right = try await devices.send(
                createTask("Synthetic car service", requestID: "l20-unauth-0001", credential: credential))
            #expect(right.status == 201)
            #expect(!APIExchange.isReplay(right))

            // 429: once the window has passed, the same request is applied.
            testHost.advance(minutes: 1)
            for _ in 1...300 {
                _ = try await devices.send(
                    APIExchange.request(.listTasks, query: ["limit": "1"], credential: credential))
            }
            let throttledRequest = try createTask(
                "Synthetic bike repair", requestID: "l20-throttle-01", credential: credential)
            APIExchange.expectError(try await devices.send(throttledRequest), .throttled)
            testHost.advance(minutes: 1)
            let later = try await devices.send(throttledRequest)
            #expect(later.status == 201)
            #expect(!APIExchange.isReplay(later))
            #expect(try host.application.all(LisaTask.self).count == 2)

            // 503: this host cannot read captured links; the retry runs again rather than replaying.
            let link = try await OwnerClient.inProcess(host).capture(
                CaptureRequestDTO(kind: .link, url: "https://example.com/synthetic-page", channel: .api))
            let retrieve = APIExchange.request(
                .retrieveCapture(id: link.id), requestID: "l20-retrieve-0001", credential: credential)
            APIExchange.expectError(try await devices.send(retrieve), .unavailable)
            let again = try await devices.send(retrieve)
            APIExchange.expectError(again, .unavailable)
            #expect(!APIExchange.isReplay(again))
            host.close()
        }
    }

    @Test("Duplicates arriving at the same moment are applied once")
    func concurrentDuplicatesAreAppliedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host, credential) = try await hostWithPhone(scratch)
            let devices = host.deviceTransport
            let request = try createTask(
                "Synthetic boiler check", requestID: "l20-concurrent-01", credential: credential)
            let responses = await withTaskGroup(of: APIResponse?.self) { group in
                for _ in 1...8 {
                    group.addTask { try? await devices.send(request) }
                }
                var collected: [APIResponse] = []
                for await response in group {
                    if let response { collected.append(response) }
                }
                return collected
            }
            #expect(responses.count == 8)
            #expect(responses.filter { $0.status == 201 && !APIExchange.isReplay($0) }.count == 1)
            for response in responses where response.status != 201 {
                let body = APIExchange.expectError(response, .unavailable)
                #expect((body?.retryAfterSeconds ?? 0) > 0)
            }
            #expect(try host.application.all(LisaTask.self).count == 1)
            let later = try await devices.send(request)
            #expect(later.status == 201)
            #expect(APIExchange.isReplay(later))
            host.close()
        }
    }

    @Test("Pairing and pairing-code responses are never recorded")
    func pairingResponsesAreNotRecorded() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let codeRequest = APIExchange.request(.createPairingCode, requestID: "l20-code-00001")
            let firstCode = try await host.ownerTransport.send(codeRequest)
            let secondCode = try await host.ownerTransport.send(codeRequest)
            #expect(firstCode.status == 201)
            #expect(secondCode.status == 201)
            #expect(!APIExchange.isReplay(secondCode))
            let code = try APIExchange.decode(PairingCodeDTO.self, firstCode)
            #expect(code.code != (try APIExchange.decode(PairingCodeDTO.self, secondCode)).code)

            let pair = APIExchange.request(
                .pairDevice,
                body: try APIExchange.json(
                    PairDeviceRequest(
                        code: code.code, installationID: SyntheticDevice.randomHex(bytes: 16),
                        name: "Synthetic iPhone", deviceClass: .iPhone, appBundleID: SyntheticDevice.companionBundleID,
                        environment: .development)),
                requestID: "l20-pair-000001")
            let paired = try await host.deviceTransport.send(pair)
            #expect(paired.status == 201)
            // The same request again does not hand out the credential a second time: the code is spent.
            let repeated = try await host.deviceTransport.send(pair)
            APIExchange.expectError(repeated, .unauthenticated)
            #expect(!APIExchange.isReplay(repeated))
            let credential = try APIExchange.decode(PairDeviceResponse.self, paired).credential
            #expect(!String(decoding: repeated.body, as: UTF8.self).contains(credential))
            host.close()
        }
    }
}
