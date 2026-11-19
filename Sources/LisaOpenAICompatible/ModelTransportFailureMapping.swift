// Maps HTTP transport failures (no usable reply from the model endpoint) to the inference module's errors.

import LisaHTTP
import LisaInference

/// Transport failures. A cancelled exchange becomes `CancellationError`, so cancellation is reported as such.
enum ModelTransportFailureMapping {
    static func error(for failure: HTTPFailure) -> any Error {
        switch failure {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return ModelError.timeout
        case .refused(let reason):
            return ModelError.refusedByPolicy("Lisa's network policy refused the connection to the endpoint: \(reason)")
        case .notSent(let reason):
            return ModelError.unavailable("the endpoint could not be reached: \(reason)")
        case .untrustedServer:
            return ModelError.unavailable("the endpoint's TLS certificate could not be verified, so nothing was sent")
        case .connectionLost:
            return ModelError.unavailable("the connection to the endpoint was lost during the request")
        case .responseTooLarge(let limit):
            return ModelError.invalidResponse("the reply exceeded \(limit) bytes")
        case .protocolError:
            return ModelError.invalidResponse("the endpoint's reply was not valid HTTP")
        case .redirectRefused:
            return ModelError.unavailable("the endpoint redirected the request, which Lisa does not follow")
        case .unsupported(let reason):
            return ModelError.unavailable("the HTTP transport cannot send this request: \(reason)")
        case .http2Unavailable:
            return ModelError.unavailable("the HTTP transport could not negotiate the required protocol")
        }
    }
}
