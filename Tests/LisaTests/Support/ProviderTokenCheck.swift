// Test-only cross-check (plan §10): reads an APNs provider token, a JWS compact serialization, and verifies its ES256
// signature with the openssl CLI against the public key of the synthetic signing key, independently of LisaCrypto.
// The key and the signature are written only into the test's scratch directory. Used by the APNs adapter contract
// suite (L27).

import Foundation

/// A provider token taken apart, as APNs would read it.
struct ProviderTokenCheck {
    /// The decoded JOSE header, such as `alg` and `kid`.
    let header: [String: Any]
    /// The decoded claims, such as `iss` and `iat`.
    let claims: [String: Any]
    /// `base64url(header) "." base64url(claims)`, the bytes the signature covers.
    let signingInput: String
    /// The raw `r || s` signature.
    let signature: Data

    /// Takes `jwt` apart; nil unless it has three base64url parts, two JSON objects and a 64-byte signature.
    init?(_ jwt: String) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = Self.base64URL(parts[0]), let claimsData = Self.base64URL(parts[1]),
            let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
            let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
            let signature = Self.base64URL(parts[2]), signature.count == 64
        else { return nil }
        self.header = header
        self.claims = claims
        signingInput = parts[0] + "." + parts[1]
        self.signature = signature
    }

    /// Whether `openssl dgst -sha256 -verify` accepts the signature over `input` (the token's own signing input by
    /// default) with the public key of `privateKeyPEM`. Files are written under `directory`.
    func verifies(withKey privateKeyPEM: String, in directory: URL, input: String? = nil) async throws -> Bool {
        let folder = directory.appendingPathComponent("token-check-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = folder.appendingPathComponent("signing.pem")
        try Data(privateKeyPEM.utf8).write(to: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        try Data((input ?? signingInput).utf8).write(to: folder.appendingPathComponent("input.txt"))
        try Self.der(signature).write(to: folder.appendingPathComponent("signature.der"))
        try await OpenSSLCommand.run(["pkey", "-in", "signing.pem", "-pubout", "-out", "public.pem"], in: folder)
        let outcome = try await OpenSSLCommand.outcome(
            ["dgst", "-sha256", "-verify", "public.pem", "-signature", "signature.der", "input.txt"], in: folder)
        let report = String(decoding: outcome.output, as: UTF8.self)
        if outcome.status == 0 && report.contains("Verified OK") { return true }
        guard report.contains("Verification failure") else {
            throw OpenSSLCommand.Failed(description: "openssl dgst did not check the signature: \(outcome.errors)")
        }
        return false
    }

    /// The DER `ECDSA-Sig-Value` (a SEQUENCE of the INTEGERs r and s) that openssl reads, from a raw `r || s`.
    static func der(_ raw: Data) -> Data {
        func integer(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
            var value = Array(bytes.drop { $0 == 0 })
            if value.isEmpty { value = [0] }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return [0x02, UInt8(value.count)] + value
        }
        let bytes = [UInt8](raw)
        let body = integer(bytes[0..<32]) + integer(bytes[32..<64])
        return Data([0x30, UInt8(body.count)] + body)
    }

    /// Base64url without padding (RFC 7515 §2), decoded.
    static func base64URL(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }
}
