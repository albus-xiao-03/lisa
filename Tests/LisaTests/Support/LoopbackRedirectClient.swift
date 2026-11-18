// Test-only controlled substitute (plan §10) at the LisaHTTP boundary: sends an adapter's request through the real
// libcurl client (LisaCurl's CurlHTTPClient, which trusts only the synthetic authority) to the scripted loopback HTTPS
// server instead of the configured public host. Only the origin and the address policy change, because the
// production policy never lets these sources reach a loopback address; the path, query, headers, body, version,
// size and time limits stay the adapter's own, and the response is reported for the adapter's own address. Used by
// the feed contract suite (L18).

import Foundation
import LisaCurl
import LisaHTTP

/// Routes every request to `https://127.0.0.1:<port>` through libcurl.
struct LoopbackRedirectClient: HTTPClient {
    /// Why the client could not be created.
    struct Unusable: Error, CustomStringConvertible {
        let description: String
    }

    private let client: CurlHTTPClient
    private let port: Int

    /// - Parameters:
    ///   - port: the scripted server's port on 127.0.0.1.
    ///   - trustStore: the synthetic authority, the only one the client trusts.
    init(port: Int, trustStore: URL) throws {
        do {
            client = try CurlHTTPClient(configuration: .init(trustStorePath: trustStore.path, userAgent: "Lisa"))
        } catch {
            throw Unusable(description: "libcurl is unavailable: \(error)")
        }
        self.port = port
    }

    var capabilities: HTTPClientCapabilities { client.capabilities }

    func send(_ request: HTTPRequest) async throws(HTTPFailure) -> HTTPResponse {
        guard var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else {
            throw .refused("the test could not route the request to the loopback server")
        }
        components.scheme = "https"
        components.host = "127.0.0.1"
        components.port = port
        guard let routedURL = components.url else {
            throw .refused("the test could not route the request to the loopback server")
        }
        var routed = request
        routed.url = routedURL
        routed.addresses = .allowLocalNetworks
        var response = try await client.send(routed)
        response.finalURL = request.url
        return response
    }
}
