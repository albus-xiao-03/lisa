// The production `CoreTransport` (plan §7.2.1, §8.6.5): the v2 sync messages over R1's `APITransport`, which in the
// apps and the X2 probe is LisaClient's `URLSessionTransport` with the trust evaluator injected. Each request carries
// the device's bearer credential and the v2 version header; any answer but 200 is an error with Core's code.

import Foundation
import LisaAPIContract
import LisaSyncEngine
import LisaSyncProtocol

/// Why a v2 request failed.
public enum HTTPCoreTransportError: Error, Hashable, Sendable {
    /// Core answered with a status other than 200, and this code and message.
    case refused(status: Int, code: String, message: String)
    /// Core's answer wasn't a valid v2 message.
    case malformed(OperationEnvelopeError)
}

/// The v2 sync routes over an `APITransport`.
public struct HTTPCoreTransport: CoreTransport {
    let transport: any APITransport
    let credential: String

    /// - Parameter credential: the device's bearer credential from pairing.
    public init(transport: any APITransport, credential: String) {
        self.transport = transport
        self.credential = credential
    }

    public func capabilities() async throws -> SyncWire.Capabilities {
        try decoded(try await send(.get, "/v2/capabilities")) { try SyncWire.capabilities(fromBody: $0) }
    }

    public func submit(_ operations: [SignedOperation]) async throws -> [SyncWire.Outcome] {
        let body = try SyncWire.submissionBody(operations)
        return try decoded(try await send(.post, "/v2/operations", body: body)) { try SyncWire.outcomes(fromBody: $0) }
    }

    public func receipts(for operationIDs: [Identifier128]) async throws -> [(
        operationID: Identifier128, receipt: SignedCoreReceipt?
    )] {
        let body = try SyncWire.lookupBody(operationIDs)
        return try decoded(try await send(.post, "/v2/receipts/lookup", body: body)) {
            try SyncWire.receipts(fromBody: $0)
        }
    }

    public func changes(partition: String, after position: Int64, limit: Int) async throws -> SignedChangePage? {
        let response = try await send(
            .get, "/v2/changes", query: ["partition": partition, "after": String(position), "limit": String(limit)])
        return try decoded(response) { try SyncWire.page(fromBody: $0) }
    }

    func send(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: [UInt8]? = nil) async throws
        -> APIResponse
    {
        var headers = ["Authorization": "Bearer " + credential, "Lisa-API-Version": SyncWire.apiVersion]
        if body != nil { headers["Content-Type"] = "application/json" }
        let response = try await transport.send(
            APIRequest(method: method, path: path, query: query, headers: headers, body: body.map { Data($0) }))
        guard response.status == 200 else {
            var code = "unknown"
            var message = ""
            if let object = try? CanonicalDecoder.decode(
                [UInt8](response.body), limits: CanonicalLimits(maxBytes: 4_096)),
                case .object(let fields) = object
            {
                if case .string(let text)? = fields["code"] { code = text }
                if case .string(let text)? = fields["message"] { message = text }
            }
            throw HTTPCoreTransportError.refused(status: response.status, code: code, message: message)
        }
        return response
    }

    func decoded<T>(_ response: APIResponse, _ decode: ([UInt8]) throws -> T) throws -> T {
        do {
            return try decode([UInt8](response.body))
        } catch let error as OperationEnvelopeError {
            throw HTTPCoreTransportError.malformed(error)
        }
    }
}
