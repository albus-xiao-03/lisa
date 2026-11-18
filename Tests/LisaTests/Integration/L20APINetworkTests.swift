// Integration tests for L20 over loopback (API-01, API-03; D-44, D-45): the host's real network server, reached
// through the companions' URLSession transport, the CLI's libcurl transport and raw HTTP/1.1, serves the same
// contract as in process: pairing on the device listener with a code from the owner listener, replays, conflicts and
// pagination. Each listener accepts only its own credential, a 401 carries `WWW-Authenticate: Bearer realm="lisa"`,
// and a run's owner credential stops working when serving stops; every response carries `Cache-Control: no-store`,
// `X-Content-Type-Options: nosniff` and the API version; the server's own framing rules (405 with Allow; 400 for
// malformed requests, conflicting framing, missing or repeated singleton fields and badly encoded targets; 413; 417;
// 431) answer with the typed error body and close the connection; plain HTTP is refused off loopback. Loopback only;
// device registrations are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L20 — API behavior over loopback", .tags(.integration))
struct L20APINetworkTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    /// A host serving over loopback on a free device port.
    private func serving(_ scratch: ScratchDirectory) async throws -> (TestHost, LisaHost, LoopbackAPIServer) {
        var testHost = TestHost(scratch: scratch, now: start)
        testHost.settings.api = LoopbackAPIServer.settings()
        let host = try testHost.open()
        return (testHost, host, try await LoopbackAPIServer.start(for: host))
    }

    private func expectServerHeaders(_ response: APIResponse, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(response.header("Cache-Control") == "no-store", sourceLocation: sourceLocation)
        #expect(response.header("X-Content-Type-Options") == "nosniff", sourceLocation: sourceLocation)
        #expect(response.header("Lisa-API-Version") == "1.0", sourceLocation: sourceLocation)
    }

    @Test("Over loopback, the device listener serves the same contract: pairing, replays, conflicts and pages")
    func deviceListenerServesTheContract() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, server) = try await serving(scratch)
            let transport = try server.deviceTransport()
            defer { transport.invalidate() }
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: transport, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: server.ownerClient())
            #expect(try await phone.client.installation().isPaired)
            #expect(try await phone.client.devices().map(\.id) == [phoneID])
            let credential = try #require(try phone.credential())

            let create = APIExchange.request(
                .createTask, body: try APIExchange.json(TaskCreateRequest(title: "Synthetic warranty claim")),
                requestID: "l20-net-create-01", credential: credential)
            let first = try await transport.send(create)
            #expect(first.status == 201)
            #expect(!APIExchange.isReplay(first))
            let second = try await transport.send(create)
            #expect(second.status == 201)
            #expect(APIExchange.isReplay(second))
            #expect(second.body == first.body)
            expectServerHeaders(first)
            expectServerHeaders(second)
            #expect(try host.application.all(LisaTask.self).count == 1)

            let task = try APIExchange.decode(TaskDTO.self, first)
            let stale = try await transport.send(
                APIExchange.request(
                    .updateTask(id: task.id),
                    body: try APIExchange.json(TaskPatchRequest(expectedRevision: task.revision + 3, title: "x")),
                    requestID: RequestID.random(), credential: credential))
            #expect(APIExchange.expectError(stale, .conflict)?.currentRevision == task.revision)
            expectServerHeaders(stale)
            _ = try await phone.client.createTask(TaskCreateRequest(title: "Synthetic second claim"))
            let page = try await phone.client.tasks(limit: 1)
            #expect(page.items.count == 1)
            let cursor = try #require(page.nextCursor)
            let next = try await phone.client.tasks(limit: 1, cursor: cursor)
            #expect(next.items.count == 1)
            #expect(next.nextCursor == nil)
            #expect(Set((page.items + next.items).map(\.id)).count == 2)
            APIExchange.expectError(
                try await transport.send(
                    APIExchange.request(.listTasks, query: ["limit": "0"], credential: credential)),
                .invalidRequest, field: "limit")
            await server.stop()
            host.close()
        }
    }

    @Test("Each listener accepts only its own credential, and a 401 asks for a bearer credential")
    func listenersAcceptOnlyTheirOwnCredential() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, server) = try await serving(scratch)
            let transport = try server.deviceTransport()
            defer { transport.invalidate() }
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: transport, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: server.ownerClient())
            let credential = try #require(try phone.credential())
            let ownerTransport = try LoopbackOwnerTransport(
                port: server.ownerPort, network: .libcurl(userAgent: "lisa-tests"))

            // The device listener: no credential, or the owner credential, is refused.
            for request in [
                APIExchange.request(.listTasks), APIExchange.request(.listTasks, credential: server.ownerCredential),
            ] {
                let response = try await transport.send(request)
                APIExchange.expectError(response, .unauthenticated)
                #expect(response.header("WWW-Authenticate") == #"Bearer realm="lisa""#)
                expectServerHeaders(response)
            }

            // The owner listener: only the owner credential is accepted.
            for presented in [nil, credential] {
                let response = try await ownerTransport.send(
                    APIExchange.request(.createPairingCode, requestID: RequestID.random(), credential: presented))
                APIExchange.expectError(response, .unauthenticated)
                #expect(response.header("WWW-Authenticate") == #"Bearer realm="lisa""#)
            }
            let issued = try await ownerTransport.send(
                APIExchange.request(
                    .createPairingCode, requestID: RequestID.random(), credential: server.ownerCredential))
            #expect(issued.status == 201)
            expectServerHeaders(issued)

            // A removed device gets 401 over the network too.
            try await server.ownerClient().removeDevice(id: phoneID)
            let removed = try await transport.send(APIExchange.request(.listTasks, credential: credential))
            APIExchange.expectError(removed, .unauthenticated)
            #expect(removed.header("WWW-Authenticate") == #"Bearer realm="lisa""#)

            // When serving stops, the run's owner credential stops working; the next run issues another.
            await server.stop()
            let nextRun = try await LoopbackAPIServer.start(for: host)
            let nextOwner = try LoopbackOwnerTransport(
                port: nextRun.ownerPort, network: .libcurl(userAgent: "lisa-tests"))
            APIExchange.expectError(
                try await nextOwner.send(
                    APIExchange.request(
                        .createPairingCode, requestID: RequestID.random(), credential: server.ownerCredential)),
                .unauthenticated)
            #expect(nextRun.ownerCredential != server.ownerCredential)
            #expect(
                try await nextOwner.send(
                    APIExchange.request(
                        .createPairingCode, requestID: RequestID.random(), credential: nextRun.ownerCredential)
                ).status == 201)
            await nextRun.stop()
            host.close()
        }
    }

    @Test("The server's own framing rules answer with the typed error body and close the connection")
    func framingRulesAnswerAndClose() async throws {
        try await ScratchDirectory.with { scratch in
            let (_, host, server) = try await serving(scratch)
            let manyFields = (1...101).map { "X-Synthetic-\($0): \($0)\n" }.joined()
            let longField = "X-Synthetic-Long: " + String(repeating: "a", count: 17_000) + "\n"
            let largeBody = String(repeating: "x", count: 300_000)
            let cases: [(String, Data, Int, APIErrorCode)] = [
                ("garbage", RawHTTPExchange.crlf("NOT AN HTTP REQUEST\n\n"), 400, .invalidRequest),
                (
                    "method", RawHTTPExchange.crlf("OPTIONS /v1/health HTTP/1.1\nHost: 127.0.0.1\n\n"), 405,
                    .invalidRequest
                ),
                ("no host", RawHTTPExchange.crlf("GET /v1/health HTTP/1.1\n\n"), 400, .invalidRequest),
                (
                    "two hosts",
                    RawHTTPExchange.crlf("GET /v1/health HTTP/1.1\nHost: 127.0.0.1\nHost: example.com\n\n"),
                    400, .invalidRequest
                ),
                (
                    "length and chunked",
                    RawHTTPExchange.crlf(
                        "POST /v1/captures HTTP/1.1\nHost: 127.0.0.1\nContent-Length: 2\nTransfer-Encoding: chunked\n\n"
                            + "{}"), 400, .invalidRequest
                ),
                (
                    "repeated request ID",
                    RawHTTPExchange.crlf(
                        "POST /v1/tasks HTTP/1.1\nHost: 127.0.0.1\nLisa-Request-ID: synthetic-0001\n"
                            + "Lisa-Request-ID: synthetic-0002\nContent-Length: 2\n\n{}"), 400, .invalidRequest
                ),
                (
                    "repeated authorization",
                    RawHTTPExchange.crlf(
                        "GET /v1/tasks HTTP/1.1\nHost: 127.0.0.1\nAuthorization: Bearer a\nAuthorization: Bearer b\n\n"),
                    400, .invalidRequest
                ),
                (
                    "encoded slash", RawHTTPExchange.crlf("GET /v1/tasks/a%2Fb HTTP/1.1\nHost: 127.0.0.1\n\n"), 400,
                    .invalidRequest
                ),
                (
                    "bad query encoding", RawHTTPExchange.crlf("GET /v1/tasks?limit=%ZZ HTTP/1.1\nHost: 127.0.0.1\n\n"),
                    400, .invalidRequest
                ),
                (
                    "expectation",
                    RawHTTPExchange.crlf(
                        "POST /v1/captures HTTP/1.1\nHost: 127.0.0.1\nExpect: 200-ok\nContent-Length: 2\n\n{}"), 417,
                    .invalidRequest
                ),
                (
                    "large body",
                    RawHTTPExchange.crlf(
                        "POST /v1/captures HTTP/1.1\nHost: 127.0.0.1\nContent-Type: application/json\n"
                            + "Content-Length: \(largeBody.utf8.count)\n\n" + largeBody), 413, .payloadTooLarge
                ),
                (
                    "many fields", RawHTTPExchange.crlf("GET /v1/health HTTP/1.1\nHost: 127.0.0.1\n\(manyFields)\n"),
                    431, .invalidRequest
                ),
                (
                    "long head", RawHTTPExchange.crlf("GET /v1/health HTTP/1.1\nHost: 127.0.0.1\n\(longField)\n"), 431,
                    .invalidRequest
                ),
            ]
            for (name, request, status, code) in cases {
                let response = try await RawHTTPExchange.exchange(port: server.devicePort, request: request)
                #expect(response.status == status, "\(name)")
                #expect(response.headers["content-type"] == "application/json", "\(name)")
                #expect(response.headers["lisa-api-version"] == "1.0", "\(name)")
                #expect(response.headers["cache-control"] == "no-store", "\(name)")
                #expect(response.headers["x-content-type-options"] == "nosniff", "\(name)")
                #expect(response.headers["connection"] == "close", "\(name)")
                let body = try? APIJSON.decoder().decode(APIErrorBody.self, from: response.body)
                #expect(body?.code == code, "\(name)")
                #expect(body?.message.isEmpty == false, "\(name)")
                if status == 405 { #expect(response.headers["allow"] == "GET, POST, PUT, PATCH, DELETE") }
            }
            #expect(try host.application.all(Capture.self).isEmpty)
            #expect(try host.application.all(LisaTask.self).isEmpty)

            // A well-formed request still reaches the router, which asks for a credential.
            let plain = try await RawHTTPExchange.exchange(
                port: server.devicePort,
                request: RawHTTPExchange.crlf("GET /v1/health HTTP/1.1\nHost: 127.0.0.1\nConnection: close\n\n"))
            #expect(plain.status == 401)
            #expect(plain.headers["www-authenticate"] == #"Bearer realm="lisa""#)
            await server.stop()
            host.close()
        }
    }

    @Test("Plain HTTP is refused on an address other than loopback")
    func plainHTTPOnlyOnLoopback() async throws {
        try await ScratchDirectory.with { scratch in
            var testHost = TestHost(scratch: scratch, now: start)
            testHost.settings.api = APIServerSettings(bindAddress: "192.0.2.10", port: 0, protection: .none)
            let host = try testHost.open()
            let error = await #expect(throws: (any Error).self) {
                _ = try await LoopbackAPIServer.start(for: host)
            }
            #expect(error.map { String(describing: $0).contains("loopback") } == true)
            host.close()
        }
    }
}
