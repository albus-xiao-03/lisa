// Enrollment's signatures (plan §8.1.2): the device signs its request with the new operation key (proof that it holds
// the key it enrolls); Core signs the anchors bundle, the result and the authorization record. The device verifies
// the bundle and the whole response with the Core signing key from the owner text, never with a key the response
// itself supplies, and matches every binding to its own attempt before anything counts as enrolled.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Why an enrollment message was refused.
public enum EnrollmentVerificationError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case invalidSignature
    /// A key that isn't a canonical P-256 SubjectPublicKeyInfo.
    case invalidKey
    /// A binding that doesn't match this attempt: which one.
    case binding(String)
    case roster(RosterVerificationError)
}

/// An enrollment result whose every binding matched the attempt.
public struct VerifiedEnrollment: Hashable, Sendable {
    public let result: EnrollmentResult
    public let roster: TrustRoster
    public let authorization: DeviceAuthorization
}

/// Signs and verifies the enrollment messages.
public enum EnrollmentSigning {
    // MARK: - The request

    /// The device's request, signed by the operation key it enrolls.
    public static func signRequest(_ request: EnrollmentRequest, with operationKey: some MessageSigning) throws
        -> SignedBody
    {
        let body = try request.canonicalBody()
        return try SignedBody(
            body: body, signature: try DomainSignatures.sign(body, domain: .enrollmentRequest, with: operationKey),
            maximumBytes: EnrollmentRequest.maximumBytes)
    }

    /// SHA-256 of the exact signed request body: what the result binds and what Core compares on a retry.
    public static func requestDigest(_ signed: SignedBody) -> Digest256 { digest(signed.body) }

    /// The request, only if its keys are canonical P-256 keys and its own operation key signed it.
    public static func verifyRequest(_ signed: SignedBody) throws(EnrollmentVerificationError) -> EnrollmentRequest {
        let request: EnrollmentRequest
        do {
            request = try EnrollmentRequest.decode(body: signed.body)
        } catch {
            throw .malformed(error)
        }
        guard let key = try? P256Verifier(canonicalSPKI: request.operationKey),
            (try? P256AgreementPublicKey(canonicalSPKI: request.exportKey)) != nil
        else { throw .invalidKey }
        guard DomainSignatures.isValid(signed.signature, over: signed.body, domain: .enrollmentRequest, by: key) else {
            throw .invalidSignature
        }
        return request
    }

    // MARK: - Core's messages

    public static func signResult(_ result: EnrollmentResult, with core: some MessageSigning) throws -> SignedBody {
        let body = try result.canonicalBody()
        return try SignedBody(
            body: body, signature: try DomainSignatures.sign(body, domain: .enrollmentResult, with: core),
            maximumBytes: EnrollmentResult.maximumBytes)
    }

    public static func signAuthorization(_ authorization: DeviceAuthorization, with core: some MessageSigning) throws
        -> SignedBody
    {
        let body = try authorization.canonicalBody()
        return try SignedBody(
            body: body, signature: try DomainSignatures.sign(body, domain: .deviceAuthorization, with: core),
            maximumBytes: DeviceAuthorization.maximumBytes)
    }

    public static func signAnchors(_ bundle: TLSAnchorsBundle, with core: some MessageSigning) throws -> SignedBody {
        let body = try bundle.canonicalBody()
        return try SignedBody(
            body: body, signature: try DomainSignatures.sign(body, domain: .tlsAnchors, with: core),
            maximumBytes: TLSAnchorsBundle.maximumBytes)
    }

    /// The digest the roster carries for the anchors bundle: SHA-256 of its signed body.
    public static func anchorsDigest(_ signed: SignedBody) -> Digest256 { digest(signed.body) }

    // MARK: - On the device

    /// The anchors bundle, only if the Core signing key from the owner text signed these exact bytes, it names the
    /// dataset, and its CA certificate's SHA-256 equals the owner text's CA digest.
    public static func verifyAnchors(
        _ signed: SignedBody, dataset: Identifier128, caDigest: Digest256, coreKey: P256Verifier
    ) throws(EnrollmentVerificationError) -> TLSAnchorsBundle {
        guard DomainSignatures.isValid(signed.signature, over: signed.body, domain: .tlsAnchors, by: coreKey) else {
            throw .invalidSignature
        }
        let bundle: TLSAnchorsBundle
        do {
            bundle = try TLSAnchorsBundle.decode(body: signed.body)
        } catch {
            throw .malformed(error)
        }
        guard bundle.datasetID == dataset else { throw .binding("dataset") }
        guard digest(bundle.caCertificate) == caDigest else { throw .binding("caDigest") }
        return bundle
    }

    /// Verifies a response against the attempt that produced it: the result's signature by `coreKey` over its exact
    /// bytes; its dataset, enrollment, issuer, request digest and keys against the request; the roster as a whole and
    /// its digest; the authorization record's signature and digest; and the device ID and keys across all three.
    public static func verifyResponse(
        _ response: EnrollmentResponse, for request: EnrollmentRequest, requestDigest: Digest256,
        coreKey: P256Verifier
    ) throws(EnrollmentVerificationError) -> VerifiedEnrollment {
        guard
            DomainSignatures.isValid(
                response.result.signature, over: response.result.body, domain: .enrollmentResult, by: coreKey)
        else { throw .invalidSignature }
        let result: EnrollmentResult
        do {
            result = try EnrollmentResult.decode(body: response.result.body)
        } catch {
            throw .malformed(error)
        }
        guard result.datasetID == request.datasetID else { throw .binding("dataset") }
        guard result.enrollmentID == request.enrollmentID else { throw .binding("enrollment") }
        guard result.issuerFingerprint == request.issuerFingerprint,
            result.issuerFingerprint.bytes == coreKey.fingerprint
        else { throw .binding("issuer") }
        guard result.requestDigest == requestDigest else { throw .binding("requestDigest") }
        guard result.operationKey == request.operationKey, result.exportKey == request.exportKey else {
            throw .binding("keys")
        }
        let roster: TrustRoster
        do {
            roster = try RosterSigning.verify(response.roster, dataset: request.datasetID, coreKey: coreKey)
        } catch {
            throw .roster(error)
        }
        guard RosterSigning.digest(response.roster) == result.rosterDigest else { throw .binding("rosterDigest") }
        guard let device = roster.device(result.deviceID), device.status == .active,
            device.operationKey == request.operationKey, device.exportKey == request.exportKey
        else { throw .binding("rosterDevice") }
        guard
            DomainSignatures.isValid(
                response.authorization.signature, over: response.authorization.body, domain: .deviceAuthorization,
                by: coreKey)
        else { throw .invalidSignature }
        let authorization: DeviceAuthorization
        do {
            authorization = try DeviceAuthorization.decode(body: response.authorization.body)
        } catch {
            throw .malformed(error)
        }
        guard digest(response.authorization.body) == result.authorizationDigest else {
            throw .binding("authorizationDigest")
        }
        guard authorization.datasetID == request.datasetID, authorization.deviceID == result.deviceID,
            authorization.epochID == roster.epochID, authorization.rosterVersion == roster.version,
            authorization.operationKey == request.operationKey
        else { throw .binding("authorization") }
        return VerifiedEnrollment(result: result, roster: roster, authorization: authorization)
    }

    static func digest(_ bytes: [UInt8]) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(bytes))))
    }
}
