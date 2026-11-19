// Test-only controlled substitute (plan §10) at the ModelProvider boundary: it answers with scripted replies or errors
// in order and records every request, with no network. Used by L04, L14, L19, L22 and later model tests (L09, L10).

import Foundation
import LisaInference
import Synchronization

/// A scripted stand-in for a model. It is labeled `scripted-test-model` and is never presented as inference.
final class ScriptedModelProvider: ModelProvider {
    /// One scripted reply, used for one request.
    enum Step: Sendable {
        /// Answer with this text.
        case respond(String)
        /// Fail with this provider error.
        case fail(ModelError)
        /// Fail with an error that is not a ``ModelError``.
        case failUnclassified
    }

    /// The error thrown for ``Step/failUnclassified``.
    struct UnclassifiedFailure: Error {}

    private struct State {
        var steps: [Step]
        var requests: [ModelRequest] = []
    }

    let descriptor: ModelDescriptor
    private let state: Mutex<State>

    /// - Parameters:
    ///   - location: where the substitute claims to run; it drives the pipeline's data-sharing check.
    ///   - steps: the replies, in order. A request after the last step fails as "unavailable".
    init(location: ModelLocation = .localNetwork, steps: [Step]) {
        descriptor = ModelDescriptor(name: "scripted-test-model", location: location, isDeterministic: false)
        state = Mutex(State(steps: steps))
    }

    func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let step = state.withLock { state -> Step? in
            state.requests.append(request)
            return state.steps.isEmpty ? nil : state.steps.removeFirst()
        }
        switch step {
        case .respond(let text): return ModelResponse(text: text, finishReason: "stop")
        case .fail(let error): throw error
        case .failUnclassified: throw UnclassifiedFailure()
        case nil: throw ModelError.unavailable("the test script has no more replies")
        }
    }

    /// Every request received, in order.
    var requests: [ModelRequest] {
        state.withLock { $0.requests }
    }

    /// The number of requests received.
    var requestCount: Int {
        state.withLock { $0.requests.count }
    }
}
