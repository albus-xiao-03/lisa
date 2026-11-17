// Maps HTTP transport failures (nothing usable came back from Discord) to classified connector failures.

import LisaHTTP
import LisaPorts

/// Transport failures. A cancelled exchange becomes `CancellationError`, so cancellation is reported as such.
enum DiscordTransportFailureMapping {
    static func error(for failure: HTTPFailure) -> any Error {
        switch failure {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return ConnectorError(.timeout, "the request to Discord timed out")
        case .refused(let reason):
            return ConnectorError(.network, "Lisa's network policy refused the connection to Discord: \(reason)")
        case .notSent(let reason):
            return ConnectorError(.network, "Discord could not be reached: \(reason)")
        case .untrustedServer:
            return ConnectorError(.network, "Discord's TLS certificate could not be verified, so nothing was sent")
        case .connectionLost:
            return ConnectorError(.network, "the connection to Discord was lost during the request")
        case .responseTooLarge(let limit):
            return ConnectorError(
                .configuration,
                "a page of messages from Discord exceeded the synchronization size limit of \(limit) bytes")
        case .protocolError:
            return ConnectorError(.network, "Discord's reply was not valid HTTP")
        case .redirectRefused:
            return ConnectorError(.network, "Discord redirected the request, which Lisa does not follow")
        case .unsupported(let reason):
            return ConnectorError(.unsupported, "the HTTP transport cannot send this request: \(reason)")
        case .http2Unavailable:
            return ConnectorError(.network, "the HTTP transport could not negotiate the required protocol with Discord")
        }
    }
}
