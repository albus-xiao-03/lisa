// Test-only controlled substitute (plan §10) at the LisaHTTP boundary: an HTTP client that keeps the first requests in
// flight, as a provider that has received a request but not yet answered, until the test releases them with an
// answer; every later request goes on to another client, such as the scripted APNs provider. A request held when its
// host stops models a crash after submission. Every held request is recorded. Used by the push recovery suite (L28).

import Foundation
import LisaHTTP
import Synchronization

/// Holds requests in flight, then forwards the rest.
final class HoldingHTTPClient: HTTPClient {
    private struct State {
        var holdsLeft: Int
        var held: [HTTPRequest] = []
        var waiting: [CheckedContinuation<Result<HTTPResponse, HTTPFailure>, Never>] = []
        var released: Result<HTTPResponse, HTTPFailure>?
    }

    private let state: Mutex<State>
    private let next: any HTTPClient

    var capabilities: HTTPClientCapabilities { next.capabilities }

    /// Holds the first `count` requests and forwards every later one to `next`.
    init(holding count: Int = 1, forwardingTo next: any HTTPClient) {
        state = Mutex(State(holdsLeft: count))
        self.next = next
    }

    func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        let holds = state.withLock { state -> Bool in
            guard state.holdsLeft > 0 else { return false }
            state.holdsLeft -= 1
            state.held.append(request)
            return true
        }
        guard holds else { return try await next.send(request) }
        let result = await withCheckedContinuation { continuation in
            let answer = state.withLock { state -> Result<HTTPResponse, HTTPFailure>? in
                if let released = state.released { return released }
                state.waiting.append(continuation)
                return nil
            }
            if let answer { continuation.resume(returning: answer) }
        }
        return try result.get()
    }

    /// The requests held so far, in order, including released ones.
    var held: [HTTPRequest] {
        state.withLock { $0.held }
    }

    /// Waits until `count` requests are held, polling with a bound. Returns whether that happened in time.
    func waitUntilHeld(_ count: Int = 1, within limit: Duration = .seconds(20)) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while state.withLock({ $0.held.count }) < count {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// Answers every held request, and any held later, with `result`.
    func release(with result: Result<HTTPResponse, HTTPFailure>) {
        let waiting = state.withLock { state -> [CheckedContinuation<Result<HTTPResponse, HTTPFailure>, Never>] in
            state.released = result
            defer { state.waiting.removeAll() }
            return state.waiting
        }
        for continuation in waiting { continuation.resume(returning: result) }
    }
}
