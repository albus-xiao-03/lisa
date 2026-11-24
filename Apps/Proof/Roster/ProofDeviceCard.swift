// PROOF ONLY — Apps/Proof never ships. The text a device shows (and as a QR code) so the owner can introduce it to
// the other proof devices: `lisa-proof-card:1:` then strict base64url of canonical JSON with the device ID, a label,
// the operation key, Design A's agreement key and Design B's TLS key hash. Public values only; synthetic; local.
// It replaces enrollment for X1 alone and is never a production enrollment path (plan §8.1.2 is not involved).

import Foundation
import LisaCrypto
import LisaSyncProtocol

struct ProofDeviceCard: Sendable, Hashable {
    static let prefix = "lisa-proof-card:1:"
    static let limits = CanonicalLimits(maxBytes: 2_048)

    let deviceID: Identifier128
    /// The owner's short label (for example "mac", "iphone", "ipad"): 1–32 printable ASCII characters.
    let label: String
    let operationKey: P256Verifier
    let agreementKey: P256AgreementPublicKey
    /// SHA-256 of the canonical SPKI of the Design B TLS key; nil before this device provisioned its identity.
    let tlsKeySHA256: Digest256?

    enum Failure: Error, Equatable {
        case notACard, label
        case encoding(String)
    }

    init(
        deviceID: Identifier128, label: String, operationKey: P256Verifier, agreementKey: P256AgreementPublicKey,
        tlsKeySHA256: Digest256?
    ) throws {
        guard (1...32).contains(label.utf8.count), label.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) else {
            throw Failure.label
        }
        self.deviceID = deviceID
        self.label = label
        self.operationKey = operationKey
        self.agreementKey = agreementKey
        self.tlsKeySHA256 = tlsKeySHA256
    }

    func text() throws -> String {
        var members: [(String, CanonicalValue)] = [
            ("proofOnly", .bool(true)), ("deviceID", .string(deviceID.hex)), ("label", .string(label)),
            ("operationKey", .string(StrictBase64URL.encode(operationKey.spkiDER))),
            ("agreementKey", .string(StrictBase64URL.encode(agreementKey.spkiDER))),
        ]
        if let tlsKeySHA256 { members.append(("tlsKeySHA256", .string(tlsKeySHA256.hex))) }
        let body = try CanonicalEncoder.encode(.object(try CanonicalObject(members)), limits: Self.limits)
        return Self.prefix + StrictBase64URL.encode(body)
    }

    init(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.prefix) else { throw Failure.notACard }
        do {
            let body = try StrictBase64URL.decode(String(trimmed.dropFirst(Self.prefix.count)))
            var reader = try CanonicalFieldReader(try CanonicalDecoder.decode(body, limits: Self.limits))
            guard try reader.bool("proofOnly") else { throw Failure.notACard }
            let deviceID = try Identifier128(hex: try reader.string("deviceID"))
            let label = try reader.string("label")
            let operationKey = try P256Verifier(canonicalSPKI: try reader.bytes("operationKey"))
            let agreementKey = try P256AgreementPublicKey(canonicalSPKI: try reader.bytes("agreementKey"))
            let tls = try reader.optionalString("tlsKeySHA256").map { try Digest256(hex: $0) }
            try reader.finish()
            try self.init(
                deviceID: deviceID, label: label, operationKey: operationKey, agreementKey: agreementKey,
                tlsKeySHA256: tls)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.encoding(String(describing: error))
        }
    }
}
