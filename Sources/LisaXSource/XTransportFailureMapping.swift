// Maps HTTP transport failures (nothing usable came back from X) to classified connector failures.

import LisaHTTP
import LisaPorts

/// Transport failures. A cancelled exchange becomes `CancellationError`, so cancellation is reported as such.
enum XTransportFailureMapping {
    static func error(for failure: HTTPFailure) -> any Error {
        switch failure {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return ConnectorError(.timeout, "the request to X timed out")
        case .refused(let reason):
            return ConnectorError(.network, "Lisa's network policy refused the connection to X: \(reason)")
        case .notSent(let reason):
            return ConnectorError(.network, "X could not be reached: \(reason)")
        case .untrustedServer:
            return ConnectorError(.network, "X's TLS certificate could not be verified, so nothing was sent")
        case .connectionLost:
            return ConnectorError(.network, "the connection to X was lost during the request")
        case .responseTooLarge(let limit):
            return ConnectorError(
                .configuration, "a page of posts from X exceeded the synchronization size limit of \(limit) bytes")
        case .protocolError:
            return ConnectorError(.network, "X's reply was not valid HTTP")
        case .redirectRefused:
            return ConnectorError(.network, "X redirected the request, which Lisa does not follow")
        case .unsupported(let reason):
            return ConnectorError(.unsupported, "the HTTP transport cannot send this request: \(reason)")
        case .http2Unavailable:
            return ConnectorError(.network, "the HTTP transport could not negotiate the required protocol with X")
        }
    }
}
