// Bounds a whole fetch, redirects included, by the synchronization pass's time limit; the transport bounds each hop.

import Foundation
import LisaHTTP

/// How a bounded send ended.
package enum DeadlineOutcome: Sendable {
    case response(HTTPResponse)
    case failure(HTTPFailure)
    /// The time limit passed first; the send was cancelled.
    case expired
    /// The calling task was cancelled.
    case cancelled
}

/// Races a send against the pass's time limit. The transport applies its timeout to each exchange, so a chain of
/// slow redirects could otherwise take several times the limit (OPS-02).
package enum FetchDeadline {
    package static func send(_ request: HTTPRequest, using client: any HTTPClient, within seconds: Double) async
        -> DeadlineOutcome
    {
        let limit = seconds.isFinite && seconds > 0 ? seconds : 1
        return await withTaskGroup(of: DeadlineOutcome.self) { group in
            group.addTask {
                do throws(HTTPFailure) {
                    return .response(try await client.send(request))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .milliseconds(Int64((limit * 1_000).rounded(.up))))
                } catch {
                    return .cancelled
                }
                return .expired
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            if Task.isCancelled { return .cancelled }
            return first
        }
    }
}
