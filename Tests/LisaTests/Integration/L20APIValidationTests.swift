// Integration tests for L20, API validation and typed errors (API-02, API-03, SEC-02; D-35), through the real router
// in process as docs/API.md documents them: malformed input is a 400 naming the offending field and changes nothing;
// a mutation without a valid Lisa-Request-ID is a 400; a body over 256 KiB is a 413; unknown routes and records are
// 404s; every response carries Lisa-API-Version 1.0, errors have the documented body, and neither errors nor health
// echo private content or credentials; instants are ISO 8601 UTC with milliseconds, and instants without
// milliseconds are accepted; the typed client refuses another major API version. Device registrations are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L20 — API validation and typed errors", .tags(.integration))
struct L20APIValidationTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    private func mutation(_ route: APIRoute, _ json: String, credential: String? = nil) -> APIRequest {
        APIExchange.request(
            route, body: APIExchange.json(text: json), requestID: RequestID.random(), credential: credential)
    }

    @Test("Malformed input is a 400 that names the offending field and changes nothing")
    func malformedInputNamesTheField() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let owner = host.ownerTransport
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let credential = try #require(try phone.credential())

            let cases: [(APIRequest, String?)] = [
                (APIExchange.request(.rundown, query: ["date": "2026-02-30"]), "date"),
                (APIExchange.request(.brief, query: ["date": "16-11-2026"]), "date"),
                (APIExchange.request(.listTasks, query: ["limit": "0"]), "limit"),
                (APIExchange.request(.listTasks, query: ["limit": "201"]), "limit"),
                (APIExchange.request(.listTasks, query: ["limit": "ten"]), "limit"),
                (APIExchange.request(.listTasks, query: ["cursor": "not a cursor!"]), "cursor"),
                (APIExchange.request(.listTasks, query: ["status": "sleeping"]), "status"),
                (APIExchange.request(.listIdeas, query: ["lifecycle": "forgotten"]), "lifecycle"),
                (mutation(.capture, #"{"kind":"idea","channel":"api"}"#), "text"),
                (mutation(.capture, #"{"kind":"link","channel":"api","url":"ftp://example.com/file"}"#), "url"),
                (mutation(.capture, #"{"kind":"poem","channel":"api","text":"Synthetic"}"#), nil),
                (mutation(.createTask, #"{"title":5}"#), nil),
                (mutation(.createTask, #"{"title":"Synthetic filing","deadline":{"date":"2026-11-31"}}"#), "deadline"),
                (
                    mutation(
                        .createTask,
                        #"{"title":"Synthetic filing","deadline":{"instant":"2026-11-20T17:00:00.000Z","date":"2026-11-20"}}"#
                    ), "deadline"
                ),
                (
                    mutation(
                        .createTask,
                        #"{"title":"Synthetic filing","deadline":{"instant":"2026-11-20T17:00:00.000Z","zone":"Mars/Olympus"}}"#
                    ), "deadline.zone"
                ),
                (
                    mutation(.createTask, #"{"title":"Synthetic filing","deadline":{"instant":"2026-11-20 17:00"}}"#),
                    nil
                ),
                (APIExchange.request(.createTask, requestID: RequestID.random()), nil),
                (mutation(.updatePreferences, #"{"changes":[]}"#), "changes"),
            ]
            for (request, field) in cases {
                let response = try await owner.send(request)
                let body = APIExchange.expectError(response, .invalidRequest)
                #expect(body?.field == field, "\(request.method.rawValue) \(request.path) \(request.query)")
            }

            // The same validation applies to a paired device, including its own routes.
            let settings = Dictionary(uniqueKeysWithValues: (1...21).map { ("setting\($0)", "on") })
            let status = APIExchange.request(
                .notificationStatus,
                body: try APIExchange.json(NotificationStatusRequest(authorization: .authorized, settings: settings)),
                requestID: RequestID.random(), credential: credential)
            APIExchange.expectError(try await host.deviceTransport.send(status), .invalidRequest, field: "settings")
            let receipts = APIExchange.request(
                .notificationReceipts,
                body: try APIExchange.json(
                    NotificationReceiptsRequest(notificationIDs: (0...200).map { "synthetic-\($0)" })),
                requestID: RequestID.random(), credential: credential)
            APIExchange.expectError(
                try await host.deviceTransport.send(receipts), .invalidRequest, field: "notificationIDs")
            APIExchange.expectError(
                try await host.deviceTransport.send(
                    APIExchange.request(.listTasks, query: ["limit": "500"], credential: credential)),
                .invalidRequest, field: "limit")

            #expect(try host.application.all(LisaTask.self).isEmpty)
            #expect(try host.application.all(Capture.self).isEmpty)
            host.close()
        }
    }

    @Test("A mutation without a valid Lisa-Request-ID is a 400 and is not applied")
    func mutationsNeedAValidRequestID() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let body = try APIExchange.json(TaskCreateRequest(title: "Synthetic errand"))
            let invalid: [String?] = [
                nil, "short", "has spaces in it", String(repeating: "a", count: 129), "réservé-id",
            ]
            for requestID in invalid {
                let response = try await host.ownerTransport.send(
                    APIExchange.request(.createTask, body: body, requestID: requestID))
                APIExchange.expectError(response, .invalidRequest, field: "Lisa-Request-ID")
            }
            #expect(try host.application.all(LisaTask.self).isEmpty)

            for requestID in ["abcd-123", String(repeating: "Z", count: 128), "a.b_c:d-e9"] {
                let response = try await host.ownerTransport.send(
                    APIExchange.request(.createTask, body: body, requestID: requestID))
                #expect(response.status == 201)
            }
            #expect(try host.application.all(LisaTask.self).count == 3)
            host.close()
        }
    }

    @Test("A body over 256 KiB is a 413; one at the limit is validated as usual, and neither echoes its content")
    func oversizedBodiesAre413() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let marker = "synthetic-private-note"
            func capture(totalBytes: Int) -> Data {
                let prefix = #"{"kind":"idea","channel":"api","text":""#
                let suffix = #""}"#
                let filler = String(repeating: "x", count: totalBytes - prefix.utf8.count - suffix.utf8.count - 22)
                return Data((prefix + marker + filler + suffix).utf8)
            }
            let over = capture(totalBytes: APIVersioning.maxRequestBytes + 1)
            let atLimit = capture(totalBytes: APIVersioning.maxRequestBytes)
            #expect(over.count == 262_145)
            #expect(atLimit.count == 262_144)

            let tooLarge = try await host.ownerTransport.send(
                APIExchange.request(.capture, body: over, requestID: RequestID.random()))
            let refusal = APIExchange.expectError(tooLarge, .payloadTooLarge)
            #expect(refusal?.message.contains(marker) == false)
            let validated = try await host.ownerTransport.send(
                APIExchange.request(.capture, body: atLimit, requestID: RequestID.random()))
            let invalid = APIExchange.expectError(validated, .invalidRequest, field: "text")
            #expect(invalid?.message.contains(marker) == false)
            #expect(try host.application.all(Capture.self).isEmpty)

            // The typed client refuses such a body before sending it.
            let client = OwnerClient.inProcess(host)
            let text = String(repeating: "y", count: APIVersioning.maxRequestBytes)
            await #expect(throws: ClientError.self) {
                _ = try await client.capture(CaptureRequestDTO(kind: .idea, text: text, channel: .api))
            }
            host.close()
        }
    }

    @Test("Unknown routes and records are typed 404s")
    func unknownRoutesAndRecordsAre404() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let unknown = TaskID.random().rawValue
            let requests = [
                APIRequest(method: .get, path: "/v1/nothing-here"),
                APIRequest(method: .get, path: "/v2/tasks"),
                APIRequest(method: .delete, path: "/v1/tasks", headers: ["Lisa-Request-ID": RequestID.random()]),
                APIExchange.request(.task(id: unknown)),
                mutation(.updateTask(id: unknown), #"{"expectedRevision":1,"title":"Synthetic"}"#),
                mutation(.updateIdea(id: unknown), #"{"expectedRevision":1,"summary":"Synthetic"}"#),
                mutation(.reminderAction(id: unknown), #"{"action":"acknowledge"}"#),
                mutation(.notificationAction(id: unknown), #"{"action":"acknowledge"}"#),
                APIExchange.request(.removeDevice(id: unknown), requestID: RequestID.random()),
                APIExchange.request(.proposalCalendarFile(id: unknown)),
            ]
            for request in requests {
                let response = try await host.ownerTransport.send(request)
                APIExchange.expectError(response, .notFound)
            }
            host.close()
        }
    }

    @Test("Every response carries the API version, and health shows no credential or token")
    func responsesCarryTheVersionAndNoSecrets() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let credential = try #require(try phone.credential())
            let token = SyntheticDevice.randomToken()
            _ = try await phone.client.registerPush(
                PushRegistrationRequest(
                    token: token, environment: .development, topic: SyntheticDevice.companionBundleID))
            let devices = host.deviceTransport

            let responses = [
                try await devices.send(APIExchange.request(.health, credential: credential)),
                try await devices.send(
                    mutation(.createTask, #"{"title":"Synthetic errand"}"#, credential: credential)),
                try await devices.send(
                    mutation(.notificationReceipts, #"{"notificationIDs":["synthetic-1"]}"#, credential: credential)),
                try await host.ownerTransport.send(APIExchange.request(.export)),
                try await devices.send(APIExchange.request(.listDevices, credential: credential)),
            ]
            #expect(responses.map(\.status) == [200, 201, 204, 200, 200])
            for response in responses {
                #expect(response.header("Lisa-API-Version") == "1.0")
                let text = String(decoding: response.body, as: UTF8.self)
                #expect(!text.contains(credential))
                #expect(!text.contains(token))
            }
            let health = try APIExchange.decode(HealthDTO.self, responses[0])
            #expect(health.apiVersion == "1.0")
            #expect(health.deliveryModes["push"] == "dryRun")
            host.close()
        }
    }

    @Test("The typed client refuses an answer in another major API version and accepts another minor version")
    func clientRefusesAnotherMajorVersion() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let route = SwitchableTransport(.connected(host.deviceTransport))
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: route, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))

            route.set(.reportingVersion(host.deviceTransport, "2.0"))
            await #expect(throws: ClientError.incompatibleVersion("2.0")) {
                _ = try await phone.client.tasks()
            }
            route.set(.reportingVersion(host.deviceTransport, "1.9"))
            #expect(try await phone.client.tasks().items.isEmpty)
            host.close()
        }
    }

    @Test("Instants are ISO 8601 UTC with milliseconds; instants without milliseconds are accepted")
    func instantsAreISO8601UTCWithMilliseconds() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let response = try await host.ownerTransport.send(
                mutation(.createTask, #"{"title":"Synthetic filing","deadline":{"instant":"2026-11-20T17:00:00Z"}}"#))
            #expect(response.status == 201)
            let text = String(decoding: response.body, as: UTF8.self)
            #expect(text.contains(#""instant":"2026-11-20T17:00:00.000Z""#))
            #expect(text.contains(#""createdAt":"2026-11-16T15:00:00.000Z""#))
            let task = try APIExchange.decode(TaskDTO.self, response)
            #expect(task.deadline?.instant == TestTime.utcInstant("2026-11-20T17:00"))
            let stored = try #require(try host.application.record(LisaTask.self, id: TaskID(task.id)))
            #expect(stored.deadline == .at(instant: TestTime.utcInstant("2026-11-20T17:00"), zone: nil))
            host.close()
        }
    }
}
