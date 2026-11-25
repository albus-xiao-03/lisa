// The production `EnrollmentTransport` (plan §8.1.2, §8.6.5): the two enrollment exchanges over R1's `APITransport`.
// Each exchange gets a transport made for its TLS policy: on Apple platforms LisaClient's `URLSessionTransport` with
// the `Apps/Shared/Trust` evaluator for that policy injected, which checks every connection, reconnections included.
// The anchors GET carries no credential and no token; the POST carries only the signed request.

import Foundation
import LisaAPIContract
import LisaSyncEngine
import LisaSyncProtocol

/// The enrollment exchanges over an `APITransport` made per TLS policy.
public struct HTTPEnrollmentTransport: EnrollmentTransport {
    let makeTransport: @Sendable (_ coreURL: String, _ policy: CoreTLSPolicy) throws -> any APITransport

    /// - Parameter makeTransport: a transport to `coreURL` whose every connection enforces `policy`.
    public init(
        makeTransport: @escaping @Sendable (_ coreURL: String, _ policy: CoreTLSPolicy) throws -> any APITransport
    ) {
        self.makeTransport = makeTransport
    }

    public func fetchAnchors(coreURL: String, policy: CoreTLSPolicy) async throws -> SignedBody {
        let response = try await makeTransport(coreURL, policy).send(
            APIRequest(
                method: .get, path: "/v2/trust/tls-anchors", query: [:],
                headers: ["Lisa-API-Version": SyncWire.apiVersion], body: nil))
        guard response.status == 200 else {
            let (code, message) = HTTPEnrollmentTransport.error(response)
            throw HTTPCoreTransportError.refused(status: response.status, code: code, message: message)
        }
        do {
            return try EnrollmentWire.anchors(fromBody: [UInt8](response.body))
        } catch {
            throw HTTPCoreTransportError.malformed(error)
        }
    }

    public func postEnrollment(_ request: SignedBody, coreURL: String, policy: CoreTLSPolicy) async throws
        -> EnrollmentPostAnswer
    {
        let body = try EnrollmentWire.requestBody(request)
        let response = try await makeTransport(coreURL, policy).send(
            APIRequest(
                method: .post, path: "/v2/enrollments", query: [:],
                headers: ["Lisa-API-Version": SyncWire.apiVersion, "Content-Type": "application/json"],
                body: Data(body)))
        guard response.status == 200 else {
            return .refused(status: response.status, code: HTTPEnrollmentTransport.error(response).code)
        }
        return .response([UInt8](response.body))
    }

    /// Core's error code and message from a refusal's body.
    static func error(_ response: APIResponse) -> (code: String, message: String) {
        var code = "unknown"
        var message = ""
        if let object = try? CanonicalDecoder.decode([UInt8](response.body), limits: CanonicalLimits(maxBytes: 4_096)),
            case .object(let fields) = object
        {
            if case .string(let text)? = fields["code"] { code = text }
            if case .string(let text)? = fields["message"] { message = text }
        }
        return (code, message)
    }
}
