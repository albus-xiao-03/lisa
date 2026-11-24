// The exporter-bound body each side of a nearby session signs (plan §8.7).

import LisaSyncProtocol

/// The body each side signs with its operation key: both devices and nonces, the 32-byte TLS exporter value
/// (label `EXPORTER-lisa-nearby-v1`), and the signer's role, roster version and head. A relay between two devices
/// sees a different exporter value on each of its sessions, so the signatures fail there and the session closes.
public struct NearbyAuthenticationTranscript: Hashable, Sendable {
    /// The TLS exporter label both designs use.
    public static let exporterLabel = "EXPORTER-lisa-nearby-v1"
    public static let exporterLength = 32

    public let exporter: [UInt8]
    public let initiator: NearbyHello
    public let responder: NearbyHello
    public let signer: NearbyRole

    public init(exporter: [UInt8], initiator: NearbyHello, responder: NearbyHello, signer: NearbyRole)
        throws(TrustError)
    {
        guard exporter.count == Self.exporterLength else { throw .invalidNearbyValue("exporter") }
        guard initiator.deviceID != responder.deviceID else { throw .invalidNearbyValue("deviceID") }
        self.exporter = exporter
        self.initiator = initiator
        self.responder = responder
        self.signer = signer
    }

    /// The canonical body that is signed under `SigningDomain.nearbyAuthentication`.
    public func canonicalBody() throws(TrustError) -> [UInt8] {
        let own = signer == .initiator ? initiator : responder
        do {
            let body = CanonicalValue.object(
                try CanonicalObject([
                    ("exporter", .string(StrictBase64URL.encode(exporter))),
                    ("initiator", try side(initiator)), ("responder", try side(responder)),
                    ("signer", .string(signer.rawValue)), ("rosterEpoch", .string(own.rosterEpoch.hex)),
                    ("rosterVersion", .integer(own.rosterVersion)), ("head", .string(own.head.hex)),
                    ("protocolVersion", .integer(NearbyHello.protocolVersion)),
                ]))
            return try CanonicalEncoder.encode(body, limits: .operationBody)
        } catch {
            throw .invalidNearbyValue("transcript")
        }
    }

    func side(_ hello: NearbyHello) throws(CanonicalError) -> CanonicalValue {
        .object(
            try CanonicalObject([
                ("deviceID", .string(hello.deviceID.hex)), ("nonce", .string(StrictBase64URL.encode(hello.nonce))),
            ]))
    }
}
