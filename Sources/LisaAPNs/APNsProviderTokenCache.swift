// The provider token of one APNs connection: reused until a fixed refresh age inside Apple's 20-to-60-minute window,
// replaced early only after an expired-token response, and never logged (S11, S13).

import Foundation
import LisaCrypto
import LisaRedaction
import LisaSecrets
import Synchronization

/// Caches the provider token used on one connection. Apple: "Refresh your token no more than once every 20 minutes
/// and no less than once every 60 minutes", and APNs reports `TooManyProviderTokenUpdates` when a new token is used
/// more than once every 20 minutes on the same connection. Signing happens under the cache's lock, so concurrent
/// pushes never create two tokens for one refresh.
public final class APNsProviderTokenCache: Sendable {
    /// The age at which a token is replaced: no sooner than Apple's 20 minutes, and 10 minutes before APNs rejects a
    /// token older than one hour, leaving room for clock differences.
    public static let refreshAge: TimeInterval = 50 * 60
    /// Apple's minimum interval between token updates on one connection.
    public static let minimumUpdateInterval: TimeInterval = 20 * 60
    /// A token whose `iat` is later than the clock by more than this (the clock moved back) is replaced.
    public static let clockTolerance: TimeInterval = 60

    public let teamID: String
    public let credentials: APNsSigningCredentials
    private let secrets: any SecretStore
    private let cached = Mutex<APNsProviderToken?>(nil)

    public init(teamID: String, credentials: APNsSigningCredentials, secrets: any SecretStore) {
        self.teamID = teamID
        self.credentials = credentials
        self.secrets = secrets
    }

    /// The token to send at `now`: the cached one while it is younger than ``refreshAge``, otherwise a new one. The
    /// signing key is read from the secret store only when a token is signed.
    public func token(at now: Date) throws(APNsProviderTokenError) -> APNsProviderToken {
        try cached.withLock { (current: inout APNsProviderToken?) throws(APNsProviderTokenError) -> APNsProviderToken in
            if let token = current, Self.isFresh(token, at: now) { return token }
            let fresh = try sign(at: now)
            current = fresh
            return fresh
        }
    }

    /// A replacement for `rejected` after APNs answered `ExpiredProviderToken`. When another push already replaced
    /// it, that newer token is returned instead of signing again, so one expiry never causes two updates.
    public func replace(expired rejected: APNsProviderToken, at now: Date) throws(APNsProviderTokenError)
        -> APNsProviderToken
    {
        try cached.withLock { (current: inout APNsProviderToken?) throws(APNsProviderTokenError) -> APNsProviderToken in
            if let token = current, token != rejected, Self.isFresh(token, at: now) { return token }
            let fresh = try sign(at: now)
            current = fresh
            return fresh
        }
    }

    /// The earliest instant at which a token newer than `token` may be used on the same connection.
    public static func nextUpdateAllowed(after token: APNsProviderToken) -> Date {
        token.issuedAt.addingTimeInterval(minimumUpdateInterval)
    }

    /// Whether `token` may still be sent at `now` under the fixed refresh schedule.
    public static func isFresh(_ token: APNsProviderToken, at now: Date) -> Bool {
        let age = now.timeIntervalSince(token.issuedAt)
        return age >= -clockTolerance && age < refreshAge
    }

    private func sign(at now: Date) throws(APNsProviderTokenError) -> APNsProviderToken {
        let pem: Sensitive<String>
        do {
            pem = try secrets.secret(for: credentials.signingKey)
        } catch let error as SecretStoreError {
            throw .signingKeyUnavailable(error.description)
        } catch {
            throw .signingKeyUnavailable("the secret store could not provide secret \(credentials.signingKey)")
        }
        let signer: ES256Signer
        do {
            signer = try ES256Signer(pemPrivateKey: pem.revealed)
        } catch {
            throw .invalidSigningKey
        }
        return try APNsProviderToken.sign(teamID: teamID, keyID: credentials.keyID, issuedAt: now, signer: signer)
    }
}
