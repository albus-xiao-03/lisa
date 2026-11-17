// URLSessionTransport's session delegate: runs each data task, collects its response within the size limit, refuses
// redirects and answers authentication challenges without credentials, except server trust through an evaluator.

import Foundation
import LisaAPIContract
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The outcome of one data task.
enum TransportOutcome: Hashable, Sendable {
    /// The host answered. Redirects and error statuses are answers too.
    case response(APIResponse)
    /// The request failed, before it was sent or after it may have been delivered.
    case failure(APITransportError)
    /// The calling task was cancelled.
    case cancelled
}

/// How the transport answers an authentication challenge.
enum ChallengeAnswer {
    /// Accept the host's TLS certificate with the evaluator's credential.
    case useCredential(URLCredential)
    /// Refuse the connection: the evaluator rejected the host's certificate.
    case refuse
    /// Let URLSession decide without a credential: system trust for TLS, and for HTTP authentication the 401 response
    /// itself, since no credential storage is configured to propose one.
    case performDefaultHandling
}

/// The delegate of a `URLSessionTransport`'s session, which keeps a strong reference to it until it is invalidated.
///
/// Every request is a delegate-driven data task (no completion handler), so that on every platform redirects are
/// offered to this delegate, which refuses them, and the body is counted while it arrives.
final class TransportSessionDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let maximumResponseBytes: Int
    private let serverTrustEvaluator: (any ServerTrustEvaluator)?
    /// The exchanges in flight, by task identifier.
    private let exchanges = Mutex<[Int: TransportExchange]>([:])

    init(maximumResponseBytes: Int, serverTrustEvaluator: (any ServerTrustEvaluator)?) {
        self.maximumResponseBytes = maximumResponseBytes
        self.serverTrustEvaluator = serverTrustEvaluator
        super.init()
    }

    /// Resumes `task` and waits for its outcome. Cancelling the calling task cancels `task` and returns `.cancelled`
    /// at once.
    func run(_ task: URLSessionDataTask) async -> TransportOutcome {
        let exchange = TransportExchange(maximumBytes: maximumResponseBytes)
        let identifier = task.taskIdentifier
        exchanges.withLock { $0[identifier] = exchange }
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<TransportOutcome, Never>) in
                exchange.wait(with: continuation)
                task.resume()
            }
        } onCancel: {
            exchange.finish(.cancelled)
            task.cancel()
        }
        exchanges.withLock { _ = $0.removeValue(forKey: identifier) }
        return outcome
    }

    /// How to answer a challenge for `protectionSpace`. Only a server-trust challenge with an evaluator configured is
    /// ever answered with a credential. swift-corelibs-foundation raises challenges only for `WWW-Authenticate: Basic`
    /// with a realm; answering one with `.useCredential` would make it resend the request with Basic credentials,
    /// again after every further 401.
    static func answer(
        toChallengeFor protectionSpace: URLProtectionSpace, isServerTrust: Bool,
        evaluator: (any ServerTrustEvaluator)?
    ) -> ChallengeAnswer {
        guard isServerTrust, let evaluator else { return .performDefaultHandling }
        guard let credential = evaluator.credential(forServerTrustOf: protectionSpace) else { return .refuse }
        return .useCredential(credential)
    }

    /// Whether `protectionSpace` asks to evaluate the host's TLS certificate. swift-corelibs-foundation raises
    /// challenges only for 401 responses with a Basic challenge, never for server trust.
    static func isServerTrust(_ protectionSpace: URLProtectionSpace) -> Bool {
        #if canImport(FoundationNetworking)
            return false
        #else
            return protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        #endif
    }

    private func exchange(for task: URLSessionTask) -> TransportExchange? {
        exchanges.withLock { $0[task.taskIdentifier] }
    }

    // MARK: - URLSessionTaskDelegate

    /// Refuses every redirect, so the 3xx response is the task's response.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        let answer = Self.answer(
            toChallengeFor: protectionSpace, isServerTrust: Self.isServerTrust(protectionSpace),
            evaluator: serverTrustEvaluator)
        switch answer {
        case .useCredential(let credential):
            completionHandler(.useCredential, credential)
        case .refuse:
            exchange(for: task)?.finish(
                .failure(.refused("the host's TLS certificate was rejected by the server trust evaluator")))
            completionHandler(.cancelAuthenticationChallenge, nil)
        case .performDefaultHandling:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let exchange = exchange(for: task) else { return }
        if let error {
            exchange.finish(.failure(TransportFailureMapping.transportError(for: error)))
        } else if let response = task.response as? HTTPURLResponse {
            exchange.complete(status: response.statusCode, headers: Self.headers(of: response))
        } else {
            exchange.finish(.failure(.interrupted("the host's answer is not an HTTP response")))
        }
    }

    // MARK: - URLSessionDataDelegate

    /// Stops at once when the declared length of an unencoded body exceeds the limit.
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let exchange = exchange(for: dataTask), !exchange.isFinished else {
            completionHandler(.cancel)
            dataTask.cancel()
            return
        }
        guard !Self.declaresBody(of: response, largerThan: maximumResponseBytes) else {
            exchange.finish(.failure(TransportExchange.oversized(limit: maximumResponseBytes)))
            completionHandler(.cancel)
            // swift-corelibs-foundation ignores the disposition, so the task is cancelled explicitly.
            dataTask.cancel()
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let exchange = exchange(for: dataTask) else {
            dataTask.cancel()
            return
        }
        if !exchange.append(data) { dataTask.cancel() }
    }

    // MARK: - Responses

    /// The response headers as text. URLSession joins repeated fields with ", ".
    static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            headers[name] = value
        }
        return headers
    }

    /// Whether `response` declares, with `Content-Length` and no content coding, a body larger than `limit`.
    private static func declaresBody(of response: URLResponse, largerThan limit: Int) -> Bool {
        guard response.expectedContentLength > Int64(limit) else { return false }
        let coding = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding")
        return coding == nil || coding?.lowercased() == "identity"
    }
}

/// One data task in flight: the response bytes received so far and the continuation waiting for its outcome. The
/// first outcome wins; later ones, such as the cancellation error that follows a refusal, are ignored.
private final class TransportExchange: Sendable {
    private struct State {
        var continuation: CheckedContinuation<TransportOutcome, Never>?
        var outcome: TransportOutcome?
        var body = Data()
    }

    private let maximumBytes: Int
    private let state = Mutex(State())

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    /// The failure for a body larger than `limit`.
    static func oversized(limit: Int) -> APITransportError {
        .interrupted("the response is larger than \(limit) bytes")
    }

    /// Whether the outcome is known.
    var isFinished: Bool { state.withLock { $0.outcome != nil } }

    /// Waits with `continuation`, which resumes at once when the outcome is already known.
    func wait(with continuation: CheckedContinuation<TransportOutcome, Never>) {
        let known = state.withLock { state -> TransportOutcome? in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let known { continuation.resume(returning: known) }
    }

    /// Adds received bytes. Returns `false` when the task should stop: the exchange is already finished, or the body
    /// exceeds the limit, which finishes it.
    func append(_ data: Data) -> Bool {
        let accepted = state.withLock { state -> Bool? in
            guard state.outcome == nil else { return nil }
            guard state.body.count + data.count <= maximumBytes else { return false }
            state.body.append(data)
            return true
        }
        if accepted == false { finish(.failure(Self.oversized(limit: maximumBytes))) }
        return accepted == true
    }

    /// Finishes with the response and the body received.
    func complete(status: Int, headers: [String: String]) {
        settle { body in .response(APIResponse(status: status, headers: headers, body: body)) }
    }

    /// Finishes with `outcome` unless the outcome is already known.
    func finish(_ outcome: TransportOutcome) {
        settle { _ in outcome }
    }

    /// Records the outcome `makeOutcome` builds from the body received, unless one is known, and resumes the waiter.
    private func settle(_ makeOutcome: (Data) -> TransportOutcome) {
        let settled = state.withLock {
            state -> (continuation: CheckedContinuation<TransportOutcome, Never>?, outcome: TransportOutcome)? in
            guard state.outcome == nil else { return nil }
            let outcome = makeOutcome(state.body)
            let continuation = state.continuation
            state.outcome = outcome
            state.continuation = nil
            state.body = Data()
            return (continuation, outcome)
        }
        guard let settled else { return }
        settled.continuation?.resume(returning: settled.outcome)
    }
}
