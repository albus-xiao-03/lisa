// Maps libcurl result codes to HTTPFailure, deciding whether request bytes may have reached the server.

import CCurl
import LisaHTTP

enum CurlFailureMapping {
    /// The failure for a transfer that ended with `code`.
    static func failure(
        _ code: CURLcode, message: String, requestSent: Bool, transfer: CurlTransfer, gate: CurlAddressGate,
        cancelled: Bool, http2Only: Bool
    ) -> HTTPFailure {
        let refusedClasses = gate.refusedClasses
        switch code {
        case CURLE_COULDNT_RESOLVE_HOST:
            return .notSent("the host name could not be resolved")
        case CURLE_COULDNT_CONNECT where !refusedClasses.isEmpty && !requestSent:
            return .refused(
                "the host resolves only to addresses Lisa does not connect to (\(describe(refusedClasses)))")
        case CURLE_COULDNT_CONNECT:
            return .notSent("the connection could not be established")
        case CURLE_ABORTED_BY_CALLBACK where cancelled:
            return .cancelled(requestSent: requestSent)
        case CURLE_ABORTED_BY_CALLBACK where !refusedClasses.isEmpty:
            return .refused("the connection is to an address Lisa does not connect to (\(describe(refusedClasses)))")
        case CURLE_WRITE_ERROR where transfer.bodyTooLarge:
            return .responseTooLarge(limit: transfer.maxBodyBytes)
        case CURLE_WRITE_ERROR where transfer.headersTooLarge:
            return .protocolError("the response headers exceeded \(transfer.maxHeaderBytes) bytes")
        case CURLE_FILESIZE_EXCEEDED:
            return .responseTooLarge(limit: transfer.maxBodyBytes)
        case CURLE_OPERATION_TIMEDOUT:
            return .timedOut(requestSent: requestSent)
        case CURLE_PEER_FAILED_VERIFICATION:
            return .untrustedServer(message)
        case CURLE_SSL_CACERT_BADFILE:
            return .notSent("the trust store could not be read: \(message)")
        case CURLE_SSL_CONNECT_ERROR where http2Only && !requestSent:
            return .notSent("the TLS handshake failed; the server may not offer HTTP/2: \(message)")
        case CURLE_SSL_CONNECT_ERROR:
            return requestSent ? .connectionLost(requestSent: true, message) : .notSent("TLS setup failed: \(message)")
        case CURLE_UNSUPPORTED_PROTOCOL:
            return .refused("the address uses a scheme this request does not allow")
        case CURLE_URL_MALFORMAT:
            return .refused("the address is malformed")
        case CURLE_HTTP2 where !requestSent && http2Only:
            return .http2Unavailable
        case CURLE_WEIRD_SERVER_REPLY:
            return requestSent ? .protocolError(message) : (http2Only ? .http2Unavailable : .notSent(message))
        case CURLE_GOT_NOTHING, CURLE_SEND_ERROR, CURLE_RECV_ERROR, CURLE_HTTP2, CURLE_HTTP2_STREAM, CURLE_PARTIAL_FILE:
            return .connectionLost(requestSent: requestSent, message)
        default:
            return requestSent ? .connectionLost(requestSent: true, message) : .notSent(message)
        }
    }

    private static func describe(_ classes: [AddressClass]) -> String {
        Array(Set(classes.map(\.rawValue))).sorted().joined(separator: ", ")
    }
}
