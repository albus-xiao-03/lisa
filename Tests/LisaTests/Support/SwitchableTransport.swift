// Test-only controlled substitute (plan §10) at the APITransport boundary: a client's route to the host that the test
// switches between unreachable, connected, stalled, connected but losing the host's answers, and connected to a host
// that reports another API version. Requests it lets through reach the real router unchanged, and every exchange is
// recorded. Used by the API and client suites (L10, L20, L21, L30) and later device suites.

import Foundation
import LisaAPIContract
import Synchronization

/// A client's route to the host, controlled by the test. It never answers on the host's behalf: a request either
/// reaches the host's real transport or fails as a transport failure would.
final class SwitchableTransport: APITransport {
    /// How the route behaves.
    enum Route: Sendable {
        /// Nothing reaches the host; every request fails as `APITransportError.unreachable`.
        case unreachable
        /// Requests reach `host` and its answers come back.
        case connected(any APITransport)
        /// Requests reach `host`, which handles them, but every answer is lost on the way back: the request fails as
        /// `APITransportError.interrupted`, after the host may have applied it.
        case losingAnswers(any APITransport)
        /// Requests reach `host`, which handles them, and the answer never arrives: the request waits until its caller
        /// gives up (cancellation), as when the app is stopped while waiting.
        case stalledAfterDelivery(any APITransport)
        /// Requests wait without reaching the host until their caller gives up (cancellation): a host too slow to
        /// accept them in time.
        case stalled
        /// Requests reach `host`, which handles them, but every answer reports API version `version` instead of the
        /// host's own, as a host of another API version would.
        case reportingVersion(any APITransport, String)
    }

    /// One request that reached the host, with the host's answer.
    struct Exchange: Sendable {
        var request: APIRequest
        var response: APIResponse
        /// Whether the answer was withheld from the client.
        var answerLost: Bool
    }

    /// The longest a stalled request waits for its caller to give up before it fails as interrupted, so no test can
    /// hang on it.
    static let longestStall: Duration = .seconds(60)

    private struct State {
        var route: Route
        var exchanges: [Exchange] = []
        var refused = 0
        var waiting = 0
    }

    private let state: Mutex<State>

    init(_ route: Route = .unreachable) {
        state = Mutex(State(route: route))
    }

    /// Switches the route. Requests already in flight keep the route they started on.
    func set(_ route: Route) {
        state.withLock { $0.route = route }
    }

    func send(_ request: APIRequest) async throws -> APIResponse {
        let route = state.withLock { $0.route }
        switch route {
        case .unreachable:
            state.withLock { $0.refused += 1 }
            throw APITransportError.unreachable("the synthetic route to the host is down")
        case .connected(let host):
            let response = try await host.send(request)
            record(Exchange(request: request, response: response, answerLost: false))
            return response
        case .losingAnswers(let host):
            let response = try await host.send(request)
            record(Exchange(request: request, response: response, answerLost: true))
            throw APITransportError.interrupted("the synthetic route lost the host's answer")
        case .stalledAfterDelivery(let host):
            let response = try await host.send(request)
            record(Exchange(request: request, response: response, answerLost: true))
            try await waitForCaller()
            throw APITransportError.interrupted("the synthetic route never delivered the host's answer")
        case .stalled:
            try await waitForCaller()
            throw APITransportError.interrupted("the synthetic route never reached the host")
        case .reportingVersion(let host, let version):
            var response = try await host.send(request)
            record(Exchange(request: request, response: response, answerLost: false))
            response.headers = response.headers.filter { $0.key.lowercased() != "lisa-api-version" }
            response.headers[APIVersioning.versionHeader] = version
            return response
        }
    }

    /// Every request that reached the host, in order, with its answer.
    var exchanges: [Exchange] {
        state.withLock { $0.exchanges }
    }

    /// How many requests failed because the route was down.
    var refusedCount: Int {
        state.withLock { $0.refused }
    }

    /// How many requests are waiting on a stalled route now.
    var waitingCount: Int {
        state.withLock { $0.waiting }
    }

    /// Waits until `count` requests are waiting on a stalled route, polling with a bound. Returns whether that
    /// happened in time.
    func waitUntilWaiting(_ count: Int = 1, within limit: Duration = .seconds(20)) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while waitingCount < count {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private func record(_ exchange: Exchange) {
        state.withLock { $0.exchanges.append(exchange) }
    }

    /// Waits until the calling task is cancelled (which throws `CancellationError`), or at most `longestStall`.
    private func waitForCaller() async throws {
        state.withLock { $0.waiting += 1 }
        defer { state.withLock { $0.waiting -= 1 } }
        try await Task.sleep(for: Self.longestStall)
    }
}
