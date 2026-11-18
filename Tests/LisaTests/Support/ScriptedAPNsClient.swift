// Test-only controlled substitute (plan §10) at the LisaHTTP boundary: an HTTP client that stands in for the APNs
// provider API under the real LisaAPNs adapter. It answers each push as APNs documents it (200 with the request's
// apns-id; an error status with a JSON reason, plus a timestamp for 410), always "over HTTP/2", or fails the exchange
// as a transport would, and records every request. Nothing reaches Apple or any network. Used by the live-push suites
// (L25, L29, L31, L32) and later APNs suites.

import Foundation
import LisaAPIContract
import LisaHTTP
import LisaTime
import Synchronization

/// A scripted APNs provider API. It is never presented as Apple's behavior; it only answers the adapter's requests.
final class ScriptedAPNsClient: HTTPClient {
    /// How one push is answered.
    enum Answer: Sendable {
        /// 200, echoing the request's `apns-id`.
        case accepted
        /// An error status with APNs's JSON body `{"reason": …}`, plus `"timestamp"` in milliseconds when given.
        case refused(status: Int, reason: String, timestamp: Date? = nil)
        /// The exchange fails as the transport reports it, before or after the request was sent.
        case failed(HTTPFailure)
    }

    /// One push the adapter sent, with the answer it got.
    struct Exchange: Sendable {
        var request: HTTPRequest
        var answer: Answer

        /// The device token of the request path `/3/device/<token>`.
        var deviceToken: String { request.url.lastPathComponent }
        /// The JSON payload.
        var payload: Data { request.body ?? Data() }
        /// The payload's `lisa` object.
        var lisa: LisaPushData? { PushPayload.lisaData(fromJSON: payload) }
        /// Whether the push was answered with 200.
        var wasAccepted: Bool {
            if case .accepted = answer { return true }
            return false
        }

        /// The first value of a request header, ignoring the case of its name.
        func header(_ name: String) -> String? {
            request.header(name)
        }
    }

    private struct Scripted {
        var token: String?
        var answer: Answer
    }

    private struct State {
        var scripted: [Scripted] = []
        var otherwise: Answer
        var exchanges: [Exchange] = []
    }

    private let state: Mutex<State>

    /// The adapter accepts only a client that can send HTTP/2-only requests.
    let capabilities = HTTPClientCapabilities(http2Only: true, summary: "scripted APNs substitute (test-only)")

    /// - Parameter otherwise: the answer to every push no scripted answer applies to.
    init(otherwise: Answer = .accepted) {
        state = Mutex(State(otherwise: otherwise))
    }

    /// Queues answers for the next pushes, in order. With `token`, only pushes to that device token take them.
    func script(_ answers: [Answer], forToken token: String? = nil) {
        state.withLock { state in
            state.scripted += answers.map { Scripted(token: token, answer: $0) }
        }
    }

    func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        let token = request.url.lastPathComponent
        let answer = state.withLock { state -> Answer in
            let answer: Answer
            if let index = state.scripted.firstIndex(where: { $0.token == nil || $0.token == token }) {
                answer = state.scripted.remove(at: index).answer
            } else {
                answer = state.otherwise
            }
            state.exchanges.append(Exchange(request: request, answer: answer))
            return answer
        }
        switch answer {
        case .accepted:
            return HTTPResponse(
                status: 200, headers: [HTTPHeader("apns-id", request.header("apns-id") ?? "")], body: Data(),
                version: .http2, finalURL: request.url)
        case .refused(let status, let reason, let timestamp):
            var object: [String: Any] = ["reason": reason]
            if let timestamp { object["timestamp"] = timestamp.millisecondsSince1970 }
            let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return HTTPResponse(
                status: status, headers: [HTTPHeader("content-type", "application/json")], body: body,
                version: .http2, finalURL: request.url)
        case .failed(let failure):
            throw failure
        }
    }

    /// Every push the adapter sent, in order, with its answer.
    var exchanges: [Exchange] {
        state.withLock { $0.exchanges }
    }

    /// The pushes sent to the device token `token`, in order.
    func exchanges(to token: String) -> [Exchange] {
        exchanges.filter { $0.deviceToken == token }
    }

    /// The pushes about notification `notificationID` sent to `token`, in order.
    func exchanges(to token: String, about notificationID: String) -> [Exchange] {
        exchanges(to: token).filter { $0.lisa?.notificationID == notificationID }
    }
}
