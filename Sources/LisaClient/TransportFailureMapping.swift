// Maps URL loading failures to APITransportError: never sent (unreachable), refused by TLS, or possibly delivered.

import Foundation
import LisaAPIContract

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Classifies the errors a URLSession task completes with.
///
/// - `.unreachable`: no connection was made, so the request never left.
/// - `.refused`: the TLS handshake failed or the URL was refused, before any request byte was sent.
/// - `.interrupted`: anything else, such as a lost connection, a timeout or a malformed response, after which the
///   request may have been delivered. This is the default whenever the evidence is unclear, because an offline queue
///   must keep treating such a request as possibly applied.
///
/// On Apple platforms the URLError code decides. swift-corelibs-foundation's codes are not reliable: libcurl errors it
/// does not map, TLS failures included, arrive as `.unknown`, and a refused attempt on one address (an `ECONNREFUSED`
/// that libcurl does not reset when a later address connects) turns any later failure into `.cannotConnectToHost`,
/// even after the request was sent. There, libcurl's message, which FoundationNetworking puts in the error's
/// description, decides instead: only a connect failure counts as unreachable and only a TLS handshake failure as
/// refused.
///
/// Reasons name the failure and its URLError code only, never a header, the credential, a body, the URL or
/// libcurl's message. Cancelling the calling task is reported by the transport as `CancellationError` before this
/// mapping applies.
enum TransportFailureMapping {
    /// How a failure is reported.
    enum Category: Hashable, Sendable {
        case unreachable
        case refused
        case interrupted
    }

    /// Substrings of libcurl messages for a TLS handshake or certificate verification failure.
    private static let tlsHandshakeMessages: [(text: String, summary: String)] = [
        ("SSL certificate problem", "the host's TLS certificate is not trusted"),
        ("SSL peer certificate or SSH remote key was not OK", "the host's TLS certificate is not trusted"),
        ("certificate subject name", "the host's TLS certificate does not match its name"),
        ("SSL_connect", "the TLS handshake with the host failed"),
        ("TLS connect error", "the TLS handshake with the host failed"),
        ("SSL connect error", "the TLS handshake with the host failed"),
        ("gnutls_handshake", "the TLS handshake with the host failed"),
    ]

    /// Substrings of libcurl messages for a failure to connect.
    private static let connectFailureMessages = [
        "Failed to connect to", "Could not connect to server", "Couldn't connect to server",
    ]

    /// The transport error for a task that failed with `error`.
    static func transportError(for error: any Error) -> APITransportError {
        guard let code = urlErrorCode(of: error) else {
            return .interrupted("the URL loading system failed with \(type(of: error))")
        }
        #if canImport(FoundationNetworking)
            let message = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? ""
            let (category, summary) = classify(code, libcurlMessage: message)
        #else
            let (category, summary) = classify(code, libcurlMessage: nil)
        #endif
        let reason = "\(summary) (URLError \(code.rawValue))"
        switch category {
        case .unreachable: return .unreachable(reason)
        case .refused: return .refused(reason)
        case .interrupted: return .interrupted(reason)
        }
    }

    /// The category and summary of a failure with `code`. `libcurlMessage` is swift-corelibs-foundation's error
    /// description, or `nil` where URLError codes are reliable.
    static func classify(
        _ code: URLError.Code, libcurlMessage: String?
    ) -> (category: Category, summary: String) {
        guard let message = libcurlMessage else { return (category(of: code), summary(of: code)) }
        if let tls = tlsHandshakeMessages.first(where: { message.contains($0.text) }) { return (.refused, tls.summary) }
        if connectFailureMessages.contains(where: { message.contains($0) }) {
            return (.unreachable, summary(of: .cannotConnectToHost))
        }
        switch code {
        case .cannotConnectToHost:
            return (.interrupted, "the connection failed after the request may have been sent")
        case .unknown where message.hasPrefix("end of response with"):
            return (.interrupted, "the connection closed before the response was complete")
        default:
            return (category(of: code), summary(of: code))
        }
    }

    /// The category of a URLError code, where codes are reliable.
    static func category(of code: URLError.Code) -> Category {
        switch code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet,
            .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            .unreachable
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
            .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection, .badURL, .unsupportedURL:
            .refused
        default:
            .interrupted
        }
    }

    /// A short explanation of a URLError code, free of request content.
    static func summary(of code: URLError.Code) -> String {
        switch code {
        case .cannotFindHost: "the host name could not be resolved"
        case .dnsLookupFailed: "the DNS lookup failed"
        case .cannotConnectToHost: "the connection to the host was refused or could not be made"
        case .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            "this device has no usable network connection"
        case .secureConnectionFailed: "the TLS connection could not be established"
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot: "the host's TLS certificate is not trusted"
        case .serverCertificateHasBadDate: "the host's TLS certificate has expired"
        case .serverCertificateNotYetValid: "the host's TLS certificate is not yet valid"
        case .clientCertificateRequired: "the host requires a client certificate"
        case .clientCertificateRejected: "the host rejected the client certificate"
        case .appTransportSecurityRequiresSecureConnection: "App Transport Security requires a secure connection"
        case .badURL, .unsupportedURL: "the request URL was refused"
        case .networkConnectionLost: "the connection was lost"
        case .timedOut: "the host did not answer in time"
        case .badServerResponse, .cannotParseResponse: "the host's answer is not a valid HTTP response"
        case .cancelled: "the URL loading system cancelled the request"
        default: "the URL loading system failed"
        }
    }

    /// The URLError code of `error`, which may also arrive as an `NSError` in `NSURLErrorDomain`.
    private static func urlErrorCode(of error: any Error) -> URLError.Code? {
        if let error = error as? URLError { return error.code }
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return nil }
        return URLError.Code(rawValue: error.code)
    }
}
