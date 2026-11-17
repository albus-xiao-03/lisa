// The CLI's transport to a host already running on this machine (ARCH-03 client mode): libcurl to the owner listener
// on 127.0.0.1 only, with no proxy and connect-time address checks. The owner credential travels in the Authorization
// header that the API client adds; it is marked sensitive and never logged.

import Foundation
import LisaAPIContract
import LisaHTTP

/// Sends requests to the owner listener of a running host.
public struct LoopbackOwnerTransport: APITransport {
    let port: Int
    let client: any HTTPClient
    let timeoutSeconds: Double

    /// - Parameters:
    ///   - port: the owner listener's port on 127.0.0.1, from the running host's owner endpoint file.
    ///   - timeoutSeconds: the longest one exchange may take.
    public init(port: Int, network: HostNetwork, timeoutSeconds: Double = 120) throws(HostError) {
        guard (1...65_535).contains(port) else { throw .apiUnavailable("the owner port \(port) is not valid") }
        do {
            client = try network.makeHTTPClient(.ownerClient)
        } catch {
            throw .apiUnavailable("the network library is unavailable: \(error)")
        }
        self.port = port
        self.timeoutSeconds = timeoutSeconds
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        guard let target = request.encodedTarget(), let url = URL(string: "http://127.0.0.1:\(port)\(target)") else {
            throw APITransportError.refused("the request path cannot be sent")
        }
        let headers = request.headers.sorted { $0.key < $1.key }.map { name, value in
            HTTPHeader(name, value, sensitive: name.lowercased() == APIVersioning.authorizationHeader.lowercased())
        }
        let exchange = HTTPRequest(
            method: request.method.rawValue, url: url, headers: headers, body: request.body,
            timeoutSeconds: timeoutSeconds, connectTimeoutSeconds: 5, maxResponseBytes: 16 * 1024 * 1024,
            redirects: .none, addresses: .loopbackOnly)
        let response: HTTPResponse
        do {
            response = try await client.send(exchange)
        } catch {
            if case .cancelled = error { throw CancellationError() }
            throw Self.transportError(error)
        }
        var responseHeaders: [String: String] = [:]
        for header in response.headers {
            if let existing = responseHeaders[header.name] {
                responseHeaders[header.name] = existing + ", " + header.value
            } else {
                responseHeaders[header.name] = header.value
            }
        }
        return APIResponse(status: response.status, headers: responseHeaders, body: response.body)
    }

    /// Nothing sent → the host is unreachable (retry later); possibly sent → interrupted (retry with the same request
    /// ID); refused by policy → refused.
    static func transportError(_ failure: HTTPFailure) -> APITransportError {
        switch failure {
        case .refused(let reason), .unsupported(let reason), .untrustedServer(let reason):
            .refused(reason)
        case .notSent(let reason):
            .unreachable(reason)
        default:
            failure.requestMayHaveBeenSent ? .interrupted(failure.description) : .unreachable(failure.description)
        }
    }
}
