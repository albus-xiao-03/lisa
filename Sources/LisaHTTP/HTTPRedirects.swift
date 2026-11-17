// Redirect following with every hop re-validated (SEC-02): the URL policy again, a hop limit, method rewriting per
// RFC 9110 §15.4, and credentials dropped when a hop leaves the origin. The address policy is re-applied by the
// transport when each hop connects.

import Foundation

/// Follows redirects for transports that perform single exchanges.
public enum HTTPRedirects {
    /// The statuses that carry a `Location` to follow.
    public static let followedStatuses: Set<Int> = [301, 302, 303, 307, 308]

    /// Performs `request`, following redirects as its policy allows. `exchange` performs one exchange and must not
    /// follow redirects itself.
    public static func send(
        _ request: HTTPRequest, exchange: (HTTPRequest) async throws(HTTPFailure) -> HTTPResponse
    ) async throws(HTTPFailure) -> HTTPResponse {
        var current = request
        current.url = try URLPolicy.validate(request.url, addresses: request.addresses).get()
        var hops = 0
        while true {
            var response = try await exchange(current)
            response.redirectCount = hops
            guard case .follow(let limit) = request.redirects, followedStatuses.contains(response.status),
                let location = response.header("Location")
            else { return response }
            guard hops < limit else { throw .redirectRefused("more than \(limit) redirects") }
            hops += 1
            guard let target = URL(string: location, relativeTo: current.url)?.absoluteURL else {
                throw .redirectRefused("the Location header is not a valid address")
            }
            let validated: URL
            switch URLPolicy.validate(target, addresses: request.addresses) {
            case .success(let url): validated = url
            case .failure(let failure): throw .redirectRefused(String(describing: failure))
            }
            current = next(after: current, status: response.status, to: validated)
        }
    }

    /// The request for the next hop.
    static func next(after request: HTTPRequest, status: Int, to url: URL) -> HTTPRequest {
        var next = request
        next.url = url
        let method = request.method.uppercased()
        if (status == 303 && method != "GET" && method != "HEAD")
            || ((status == 301 || status == 302) && method == "POST")
        {
            next.method = "GET"
            next.body = nil
            next.headers.removeAll { ["content-type", "content-length"].contains($0.name.lowercased()) }
        }
        if !URLPolicy.sameOrigin(request.url, url) {
            next.headers.removeAll {
                $0.isSensitive || ["cookie", "proxy-authorization"].contains($0.name.lowercased())
            }
        }
        return next
    }
}
