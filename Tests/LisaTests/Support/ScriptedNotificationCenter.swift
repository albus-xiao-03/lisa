// Test-only controlled substitute (plan §10) for the Mac app's notification center, at the LocalNotificationTransport
// boundary the platform supplies to the host: it answers each presentation with a scripted result, or holds it until
// the test releases it (a submission in flight when the host stops), and records every presentation. Nothing is shown
// anywhere. Used by the delivery suites (L16, L22) and the §16.3 recovery cases.

import Foundation
import LisaDomain
import LisaPorts
import Synchronization

/// A scripted local notification center. It is never presented as Apple behavior; it only stands in for the transport.
final class ScriptedNotificationCenter: LocalNotificationTransport {
    /// How one presentation is answered.
    enum Step: Sendable {
        /// Answer at once with this result.
        case answer(TransportResult)
        /// Keep the presentation in flight until ``release(with:)``.
        case hold
    }

    /// One presentation the host asked for.
    struct Presented: Sendable {
        var presentation: NotificationPresentation
        var deliveryID: String
    }

    private struct State {
        var steps: [Step]
        var otherwise: TransportResult
        var presented: [Presented] = []
        var held: [CheckedContinuation<TransportResult, Never>] = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - steps: the answers, in order.
    ///   - otherwise: the answer once the steps are used up.
    init(steps: [Step] = [], otherwise: TransportResult = .accepted(providerReference: nil)) {
        state = Mutex(State(steps: steps, otherwise: otherwise))
    }

    func present(_ presentation: NotificationPresentation, deliveryID: String) async -> TransportResult {
        let step = state.withLock { state -> Step in
            state.presented.append(Presented(presentation: presentation, deliveryID: deliveryID))
            return state.steps.isEmpty ? .answer(state.otherwise) : state.steps.removeFirst()
        }
        switch step {
        case .answer(let result):
            return result
        case .hold:
            return await withCheckedContinuation { continuation in
                state.withLock { $0.held.append(continuation) }
            }
        }
    }

    /// Every presentation asked for, in order, including held ones.
    var presented: [Presented] {
        state.withLock { $0.presented }
    }

    /// How many presentations are being held now.
    var heldCount: Int {
        state.withLock { $0.held.count }
    }

    /// Waits until `count` presentations are held, polling with a bound. Returns whether that happened in time.
    func waitUntilHeld(_ count: Int = 1, within limit: Duration = .seconds(20)) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while heldCount < count {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// Answers every held presentation with `result`.
    func release(with result: TransportResult) {
        let held = state.withLock { state -> [CheckedContinuation<TransportResult, Never>] in
            defer { state.held.removeAll() }
            return state.held
        }
        for continuation in held { continuation.resume(returning: result) }
    }
}
