// PROOF ONLY — Apps/Proof never ships. E-2 on the device (plan §10.5): the LisaProof build links LisaTrust,
// LisaSyncProtocol, LisaCrypto (with swift-crypto) and LisaHTTP for this Apple SDK; launching proves they built and
// linked, and this check exercises each once at run time. The case's other required evidence (scheme, destination,
// build-log digest, §10.9 R2-A01) comes from the owner's Xcode build through the harness, not from the app.
// Case IDs: OV-APPLE-X1-01 Mac, -02 iPhone, -03 iPad (the order §10.9 lists; docs/DECISIONS.md D-54).

import Foundation
import LisaCrypto
import LisaHTTP
import LisaSyncProtocol
import LisaTrust

enum E2ModuleSmokeCheck {
    static func caseID(platform: String) -> String {
        switch platform {
        case "macOS": "OV-APPLE-X1-01"
        case "iOS": "OV-APPLE-X1-02"
        default: "OV-APPLE-X1-03"
        }
    }

    /// Each portable product exercised once: name → passed.
    static func run() -> [String: Bool] {
        var results: [String: Bool] = [:]
        let signer = P256RawSigner()
        let message = Array("lisa-proof-e2".utf8)
        results["LisaCrypto.P256RawSigner+P256Verifier"] =
            (try? signer.signature(for: message)).map { signer.verifier.isValidSignature($0, for: message) } ?? false
        let first = P256AgreementKey()
        let second = P256AgreementKey()
        let dataset = Identifier128.random()
        let a = Identifier128.random()
        let b = Identifier128.random()
        let k1 = try? NearbyPairKeys.pairKey(
            ownKey: first, peerKey: second.publicKey, dataset: dataset, ownDevice: a, peerDevice: b)
        let k2 = try? NearbyPairKeys.pairKey(
            ownKey: second, peerKey: first.publicKey, dataset: dataset, ownDevice: b, peerDevice: a)
        results["LisaTrust.NearbyPairKeys symmetric"] = k1 != nil && k1 == k2
        if let object = try? CanonicalObject([("b", .integer(2)), ("a", .string("é"))]),
            let encoded = try? CanonicalEncoder.encode(.object(object), limits: CanonicalLimits(maxBytes: 64)),
            let decoded = try? CanonicalDecoder.decode(encoded, limits: CanonicalLimits(maxBytes: 64))
        {
            results["LisaSyncProtocol canonical round trip"] = decoded == .object(object)
        } else {
            results["LisaSyncProtocol canonical round trip"] = false
        }
        results["LisaHTTP NetworkAddress classification"] =
            IPLiteral.parse("10.0.0.5")?.addressClass == .privateNetwork
            && IPLiteral.parse("64:ff9b::a00:5")?.addressClass == .privateNetwork
        return results
    }
}
