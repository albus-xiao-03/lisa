// The device's key-proven trust requests over R1's `APITransport` (plan §8.1.4, §8.1.5): a credential reset and a
// challenge. Neither carries a credential, because the device's may be lost or rewound; the reset is proved by the
// owner's one-time token and the device's existing operation key, and a challenge is answered with that key.

import Foundation
import LisaAPIContract
import LisaSyncProtocol

/// Credential reset and challenge issue over an `APITransport` that enforces Core's TLS policy.
public struct HTTPTrustRequests: Sendable {
    let transport: any APITransport

    public init(transport: any APITransport) {
        self.transport = transport
    }

    /// `POST /v2/devices/current/credential-reset` with the signed request; Core's device ID and reset time.
    public func resetCredential(_ signed: SignedBody) async throws -> (deviceID: Identifier128, resetAt: Int64) {
        let body = try EnrollmentWire.requestBody(signed)
        let response = try await send(.post, "/v2/devices/current/credential-reset", body)
        do {
            return try CredentialResetRequest.answer(fromBody: [UInt8](response.body))
        } catch {
            throw HTTPCoreTransportError.malformed(error)
        }
    }

    /// `POST /v2/challenges` for `device` and `purpose`.
    public func challenge(device: Identifier128, purpose: ChallengePurpose) async throws -> Challenge {
        let response = try await send(
            .post, "/v2/challenges", try Challenge.requestBody(deviceID: device, purpose: purpose))
        do {
            return try Challenge.decode(body: [UInt8](response.body))
        } catch {
            throw HTTPCoreTransportError.malformed(error)
        }
    }

    /// `POST /v2/devices/current/key-update` with the update signed by both keys, under the device's credential;
    /// Core's new roster.
    public func updateKey(_ signed: SignedKeyTransition, credential: String) async throws -> SignedRoster {
        let response = try await send(
            .post, "/v2/devices/current/key-update", try DeviceKeyUpdate.requestBody(signed), credential: credential)
        do {
            return try EnrollmentWire.roster(fromBody: [UInt8](response.body))
        } catch {
            throw HTTPCoreTransportError.malformed(error)
        }
    }

    func send(_ method: HTTPMethod, _ path: String, _ body: [UInt8], credential: String? = nil) async throws
        -> APIResponse
    {
        var headers = ["Lisa-API-Version": SyncWire.apiVersion, "Content-Type": "application/json"]
        if let credential { headers["Authorization"] = "Bearer " + credential }
        let response = try await transport.send(
            APIRequest(method: method, path: path, query: [:], headers: headers, body: Data(body)))
        guard response.status == 200 else {
            let (code, message) = HTTPEnrollmentTransport.error(response)
            throw HTTPCoreTransportError.refused(status: response.status, code: code, message: message)
        }
        return response
    }
}
