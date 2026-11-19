// Test-only controlled substitute (plan §10) at the LisaHTTP boundary: an HTTP client that answers each request with
// the next scripted response or transport failure, and records every request. The test chooses its capabilities
// (whether HTTP/2-only requests are possible) and the HTTP version of each answer. Nothing reaches any network. Used
// by the adapter suites (L18 X, Discord and Twilio; L27 APNs).

import Foundation
import LisaHTTP
import Synchronization

/// A scripted HTTP exchange partner. It is never presented as a provider's behavior; it only answers the requests made.
final class ScriptedHTTPClient: HTTPClient {
    /// How one request is answered.
    enum Step: Sendable {
        /// A response, over `version`.
        case respond(status: Int, headers: [HTTPHeader] = [], body: Data = Data(), version: HTTPVersion = .http11)
        /// The exchange fails as the transport reports it, before or after the request was sent.
        case fail(HTTPFailure)
    }

    private struct State {
        var steps: [Step]
        var otherwise: Step
        var requests: [HTTPRequest] = []
    }

    private let state: Mutex<State>
    let capabilities: HTTPClientCapabilities

    /// - Parameters:
    ///   - steps: the answers to the first requests, in order.
    ///   - otherwise: the answer once `steps` are used up; by default the request is not sent.
    ///   - http2Only: whether the client claims it can send HTTP/2-only requests.
    init(_ steps: [Step] = [], otherwise: Step = .fail(.notSent("no scripted answer")), http2Only: Bool = false) {
        state = Mutex(State(steps: steps, otherwise: otherwise))
        capabilities = HTTPClientCapabilities(
            http2Only: http2Only, summary: "scripted HTTP client (test-only)" + (http2Only ? ", HTTP/2-only" : ""))
    }

    /// Queues answers for the next requests, after those already queued.
    func script(_ steps: [Step]) {
        state.withLock { $0.steps += steps }
    }

    func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        let step = state.withLock { state -> Step in
            state.requests.append(request)
            return state.steps.isEmpty ? state.otherwise : state.steps.removeFirst()
        }
        switch step {
        case .respond(let status, let headers, let body, let version):
            return HTTPResponse(status: status, headers: headers, body: body, version: version, finalURL: request.url)
        case .fail(let failure):
            throw failure
        }
    }

    /// Every request received, in order.
    var requests: [HTTPRequest] {
        state.withLock { $0.requests }
    }
}
