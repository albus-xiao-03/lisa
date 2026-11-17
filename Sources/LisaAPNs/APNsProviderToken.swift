// APNs provider tokens: JWTs with header fields `alg` (ES256) and `kid` and claims `iss` and `iat`, signed through
// LisaCrypto (S11).

import Foundation
import LisaCrypto
import LisaRedaction

/// One signed provider token. Its value is sent only in the `authorization` header and never logged or described.
public struct APNsProviderToken: Hashable, Sendable, CustomStringConvertible {
    /// The JWT: base64url header, claims and ES256 signature, separated by dots.
    public let jwt: Sensitive<String>
    /// The `iat` claim, in whole seconds.
    public let issuedAt: Date
    /// The `kid` header field.
    public let keyID: String

    public var description: String {
        "APNs provider token for key \(keyID) issued at \(APNsEpochSeconds.of(issuedAt)) (value redacted)"
    }

    /// Signs a new token with exactly the four fields Apple lists: header `alg` and `kid`, claims `iss` and `iat`.
    /// `issuedAt` is truncated to whole seconds, since `iat` is an integer number of seconds since 1970.
    public static func sign(teamID: String, keyID: String, issuedAt: Date, signer: ES256Signer)
        throws(APNsProviderTokenError) -> APNsProviderToken
    {
        guard APNsSettings.isTenCharacterIdentifier(teamID), APNsSettings.isTenCharacterIdentifier(keyID) else {
            throw .invalidIdentifiers
        }
        let seconds = APNsEpochSeconds.of(issuedAt)
        let input = signingInput(teamID: teamID, keyID: keyID, issuedAtSeconds: seconds)
        let signature: Data
        do {
            signature = try signer.sign(Data(input.utf8))
        } catch {
            throw .signingFailed
        }
        return APNsProviderToken(
            jwt: Sensitive("\(input).\(Base64URL.encode(signature))"),
            issuedAt: Date(timeIntervalSince1970: TimeInterval(seconds)), keyID: keyID)
    }

    /// `base64url(header) "." base64url(claims)`: the bytes the ES256 signature covers (RFC 7515). The identifiers
    /// must be validated 10-character identifiers, which need no JSON escaping.
    public static func signingInput(teamID: String, keyID: String, issuedAtSeconds: Int64) -> String {
        let header = #"{"alg":"ES256","kid":"\#(keyID)"}"#
        let claims = #"{"iss":"\#(teamID)","iat":\#(issuedAtSeconds)}"#
        return "\(Base64URL.encode(Data(header.utf8))).\(Base64URL.encode(Data(claims.utf8)))"
    }
}
