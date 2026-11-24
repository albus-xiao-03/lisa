// PROOF ONLY — Apps/Proof never ships. The shared proof setup one device generates and the owner enters on the
// other two: `lisa-proof-setup:1:` then strict base64url of canonical JSON with a synthetic dataset ID (Design A's
// HKDF salt), the roster epoch and version, and Design A's proof-only discovery secret. It stands in for
// `GET /v2/trust/nearby-secret` (plan §8.7) at X1 only. The text carries a secret: it is shown on screen only on
// the owner's request, kept in the Keychain, and never logged or written into a result.

import Foundation
import LisaCrypto
import LisaSyncProtocol

struct ProofSetupText: Sendable, Hashable {
    static let prefix = "lisa-proof-setup:1:"
    static let limits = CanonicalLimits(maxBytes: 1_024)
    static let keychainAccount = "proof-setup-text"

    let datasetID: Identifier128
    let rosterEpoch: Identifier128
    let rosterVersion: Int64
    /// 32 random bytes; nil models a device whose secret is too old (the rejoin case).
    let discoverySecret: [UInt8]?

    enum Failure: Error, Equatable {
        case notASetupText
        case encoding(String)
    }

    /// A new synthetic setup with a fresh dataset ID, epoch and discovery secret.
    static func generate() -> ProofSetupText {
        ProofSetupText(
            datasetID: .random(), rosterEpoch: .random(), rosterVersion: 1,
            discoverySecret: Array(RandomTokens.bytes(32)))
    }

    /// The same setup without the discovery secret, so the device must use the rejoin identity (plan §8.7).
    func withoutDiscoverySecret() -> ProofSetupText {
        ProofSetupText(
            datasetID: datasetID, rosterEpoch: rosterEpoch, rosterVersion: rosterVersion, discoverySecret: nil)
    }

    func text() throws -> String {
        guard let discoverySecret else { throw Failure.encoding("no discovery secret") }
        let body = try CanonicalEncoder.encode(
            .object(
                try CanonicalObject([
                    ("proofOnly", .bool(true)), ("datasetID", .string(datasetID.hex)),
                    ("rosterEpoch", .string(rosterEpoch.hex)), ("rosterVersion", .integer(rosterVersion)),
                    ("discoverySecret", .string(StrictBase64URL.encode(discoverySecret))),
                ])), limits: Self.limits)
        return Self.prefix + StrictBase64URL.encode(body)
    }

    init(datasetID: Identifier128, rosterEpoch: Identifier128, rosterVersion: Int64, discoverySecret: [UInt8]?) {
        self.datasetID = datasetID
        self.rosterEpoch = rosterEpoch
        self.rosterVersion = rosterVersion
        self.discoverySecret = discoverySecret
    }

    init(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.prefix) else { throw Failure.notASetupText }
        do {
            let body = try StrictBase64URL.decode(String(trimmed.dropFirst(Self.prefix.count)))
            var reader = try CanonicalFieldReader(try CanonicalDecoder.decode(body, limits: Self.limits))
            guard try reader.bool("proofOnly") else { throw Failure.notASetupText }
            let dataset = try Identifier128(hex: try reader.string("datasetID"))
            let epoch = try Identifier128(hex: try reader.string("rosterEpoch"))
            let version = try reader.integer("rosterVersion")
            let secret = try reader.bytes("discoverySecret")
            try reader.finish()
            guard secret.count == 32, version >= 1 else { throw Failure.encoding("secret or version") }
            self.init(datasetID: dataset, rosterEpoch: epoch, rosterVersion: version, discoverySecret: secret)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.encoding(String(describing: error))
        }
    }
}
