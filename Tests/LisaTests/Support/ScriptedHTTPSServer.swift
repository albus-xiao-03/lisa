// Test-only controlled substitute (plan §10): a loopback HTTPS server for the real libcurl paths. Lisa's own network
// server (LisaAPIServer's APIServer: HTTP/1.1 over TLS 1.2 or later) listens on 127.0.0.1 with a synthetic
// certificate, but every request goes to a scripted handler instead of Lisa's router. The handler answers with the
// next scripted response, or holds the request unanswered, as a server that stopped responding, until the server
// stops. Every request is recorded. Nothing outside this machine is reachable through it. Used by the adapter suites
// (L18).

import Foundation
import LisaAPIContract
import LisaAPIServer
import LisaLogging
import Synchronization

/// A scripted HTTPS server on 127.0.0.1. It is never presented as a real provider; it only answers the requests made.
final class ScriptedHTTPSServer: Sendable {
    /// How one request is answered.
    enum Answer: Sendable {
        /// A response with this status, these header fields and this body.
        case respond(status: Int, headers: [String: String] = [:], body: Data = Data())
        /// No answer until the server stops: the client's own time limit ends the exchange.
        case hold
    }

    /// Why the server did not start.
    struct NotStarted: Error, CustomStringConvertible {
        let description: String
    }

    private final class Script: Sendable {
        struct State {
            var answers: [Answer] = []
            var otherwise: Answer
            var requests: [APIRequest] = []
            var held: [CheckedContinuation<APIResponse, Never>] = []
            var stopped = false
        }

        let state: Mutex<State>

        init(otherwise: Answer) {
            state = Mutex(State(otherwise: otherwise))
        }

        func answer(_ request: APIRequest) async -> APIResponse {
            let answer = state.withLock { state -> Answer in
                state.requests.append(request)
                return state.answers.isEmpty ? state.otherwise : state.answers.removeFirst()
            }
            switch answer {
            case .respond(let status, let headers, let body):
                return APIResponse(status: status, headers: headers, body: body)
            case .hold:
                return await withCheckedContinuation { continuation in
                    let release = state.withLock { state -> Bool in
                        if state.stopped { return true }
                        state.held.append(continuation)
                        return false
                    }
                    if release { continuation.resume(returning: ScriptedHTTPSServer.released) }
                }
            }
        }

        /// Marks the script stopped and answers every held request.
        func stop() {
            let held = state.withLock { state -> [CheckedContinuation<APIResponse, Never>] in
                state.stopped = true
                defer { state.held.removeAll() }
                return state.held
            }
            for continuation in held { continuation.resume(returning: ScriptedHTTPSServer.released) }
        }
    }

    /// The answer a held request finally gets when the server stops, long after its client gave up.
    static let released = APIResponse(status: 503, headers: ["Content-Type": "text/plain"], body: Data("stopped".utf8))

    /// The port on 127.0.0.1.
    let port: Int
    private let server: APIServer
    private let script: Script

    private init(port: Int, server: APIServer, script: Script) {
        self.port = port
        self.server = server
        self.script = script
    }

    /// Starts serving on a free port of 127.0.0.1 with `identity`'s certificate. Requests no scripted answer applies
    /// to get `otherwise`.
    static func start(identity: SyntheticTLSIdentity, otherwise: Answer = .respond(status: 404)) async throws
        -> ScriptedHTTPSServer
    {
        let tls = try APIServerTLS(
            certificateChainPEM: Array(try Data(contentsOf: identity.certificateFile)),
            privateKeyPEM: Array(try Data(contentsOf: identity.keyFile)))
        let script = Script(otherwise: otherwise)
        let server = APIServer(
            listeners: [APIListenerConfiguration(role: .devices, address: "127.0.0.1", port: 0, transport: .tls(tls))],
            limits: APIServerLimits(shutdownGracePeriod: .seconds(1)), logger: .disabled
        ) { request, _ in
            await script.answer(request)
        }
        let bound = try await server.start()
        guard let port = bound.first?.port else {
            await server.shutdown()
            throw NotStarted(description: "the scripted HTTPS server bound no listener")
        }
        return ScriptedHTTPSServer(port: port, server: server, script: script)
    }

    /// Queues answers for the next requests, in order.
    func script(_ answers: [Answer]) {
        script.state.withLock { $0.answers += answers }
    }

    /// Every request received, in order.
    var requests: [APIRequest] {
        script.state.withLock { $0.requests }
    }

    /// Answers held requests, then stops listening and closes every connection.
    func stop() async {
        script.stop()
        await server.shutdown()
    }

    /// Runs `body` with a started server and stops it afterwards, whether `body` returns or throws.
    static func with<Result>(
        identity: SyntheticTLSIdentity, _ body: (ScriptedHTTPSServer) async throws -> Result
    ) async throws -> Result {
        let server = try await start(identity: identity)
        do {
            let result = try await body(server)
            await server.stop()
            return result
        } catch {
            await server.stop()
            throw error
        }
    }
}
