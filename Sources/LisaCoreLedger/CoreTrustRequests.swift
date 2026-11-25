// Key-proven trust requests at Core: credential reset (plan §8.1.4) and challenges (plan §8.1.5).
//
// A reset token is issued by the owner for one active device and kept only as its hash, for 10 minutes. The device
// presents it with a new verifier, signed by its existing operation key; in one write transaction Core checks the
// signature, finds the open token in constant time, and replaces the verifier, so the old credential stops working.
//
// A challenge is kept with this run's generation and a deadline on Core's monotonic clock. Verification, in one write
// transaction, requires the challenge to exist, be unused, belong to this run and the current epoch, match the
// purpose, be before its deadline, and be signed by the key the registry holds for the device, active now; only then
// is it marked used. A wall-clock step has no effect, a restart invalidates every outstanding challenge, and a device
// revoked between issue and response is refused so its upload can be quarantined.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTime
import LisaTrust

/// Why Core refused a credential reset.
public enum CoreResetRefusal: Hashable, Sendable {
    case malformed
    case unknownDevice
    case revokedDevice
    /// A wrong token, signature, dataset or verifier.
    case invalid
    case expired
    /// The token was used already.
    case used

    public var code: String {
        switch self {
        case .malformed: "invalid_request"
        case .unknownDevice: "credential_reset_unknown"
        case .revokedDevice: "device_revoked"
        case .invalid: "credential_reset_invalid"
        case .expired: "credential_reset_expired"
        case .used: "credential_reset_used"
        }
    }

    public var status: Int {
        switch self {
        case .malformed: 400
        case .unknownDevice: 404
        case .revokedDevice, .invalid: 403
        case .expired, .used: 410
        }
    }
}

/// What Core answered a credential reset.
public enum CoreResetAnswer: Hashable, Sendable {
    case reset(deviceID: Identifier128, at: Int64)
    case refused(CoreResetRefusal)
}

/// Why a challenge response was refused.
public enum CoreChallengeRefusal: Hashable, Sendable {
    case unknown
    case used
    case expired
    /// Issued before Core restarted.
    case otherRun
    /// Issued in another epoch.
    case otherEpoch
    case purposeMismatch
    /// Revoked between issue and response: the upload is kept as quarantined evidence, never admitted.
    case revokedDevice
    /// A key the merged roster doesn't know: the device's trust records reach Core only as an owner-mediated trust
    /// bundle (§8.5.3).
    case unknownKey
    case invalidSignature
}

/// What a challenge response proved.
public enum CoreChallengeVerdict: Hashable, Sendable {
    case verified(deviceID: Identifier128, purpose: ChallengePurpose)
    case refused(CoreChallengeRefusal)
}

extension CoreTrust {
    // MARK: - Credential reset (§8.1.4)

    /// Issues a one-time reset token for an active device (`lisa core device reset-credential <id>`): shown once,
    /// kept only as its hash, usable for 10 minutes. Nil for an unknown or revoked device.
    public func issueCredentialReset(_ device: Identifier128) throws(CoreLedgerError) -> CredentialResetToken? {
        let token = CredentialResetToken.random()
        let time = now()
        let issued = try ledger.write { session, _ in
            guard
                case .text("active")? = try session.query(
                    "SELECT status FROM core_devices WHERE device_id = ?", [CoreColumns.id(device)]
                ).first?.first
            else { return false }
            try session.query(
                """
                INSERT INTO core_credential_resets (reset_id, device_id, token_hash, issued_at, expires_at, state)
                VALUES (?, ?, ?, ?, ?, 'open')
                """,
                [
                    CoreColumns.id(.random()), CoreColumns.id(device), CoreColumns.bytes(token.tokenHash),
                    .integer(time),
                    .integer(time + configuration.resetLifetime),
                ])
            try Self.recordEvent("credential_reset_issued", subject: device, detail: "by the owner", time, session)
            return true
        }
        return issued ? token : nil
    }

    /// Applies a device's reset request (`POST /v2/devices/current/credential-reset`) in one write transaction.
    public func resetCredential(_ wireBody: [UInt8]) throws(CoreLedgerError) -> CoreResetAnswer {
        let signed: SignedBody
        let claimed: CredentialResetRequest
        do {
            signed = try EnrollmentWire.request(fromBody: wireBody)
            claimed = try CredentialResetRequest.decode(body: signed.body)
        } catch {
            return .refused(.malformed)
        }
        let time = now()
        return try ledger.write { session, _ in
            guard
                let device = try session.query(
                    "SELECT status, operation_key FROM core_devices WHERE device_id = ?",
                    [CoreColumns.id(claimed.deviceID)]
                ).first
            else { return .refused(.unknownDevice) }
            guard case .text("active") = device[0] else { return .refused(.revokedDevice) }
            guard let key = try? P256Verifier(canonicalSPKI: try CoreColumns.bytes(device[1])),
                let request = try? CredentialResetSigning.verify(signed, key: key), request == claimed,
                request.datasetID == self.ledger.datasetID
            else { return .refused(.invalid) }
            let presented = (try? CredentialResetToken(bytes: request.token))?.tokenHash ?? []
            var matched: (id: SQLiteValue, state: String, expiresAt: Int64)?
            let issued = try session.query(
                "SELECT reset_id, token_hash, state, expires_at FROM core_credential_resets WHERE device_id = ?",
                [CoreColumns.id(request.deviceID)])
            for row in issued {
                let stored = try CoreColumns.bytes(row[1])
                if Digests.constantTimeEquals(Data(presented), Data(stored)) {
                    matched = (row[0], try CoreColumns.text(row[2]), try CoreColumns.integer(row[3]))
                }
            }
            guard let matched else { return .refused(.invalid) }
            guard matched.state == "open" else { return .refused(matched.state == "used" ? .used : .invalid) }
            guard time < matched.expiresAt else { return .refused(.expired) }
            guard
                try session.query(
                    "SELECT 1 FROM core_devices WHERE credential_verifier = ?",
                    [CoreColumns.digest(request.newVerifier)]
                ).isEmpty
            else { return .refused(.invalid) }
            try session.query(
                "UPDATE core_devices SET credential_verifier = ? WHERE device_id = ?",
                [CoreColumns.digest(request.newVerifier), CoreColumns.id(request.deviceID)])
            try session.query("UPDATE core_credential_resets SET state = 'used' WHERE reset_id = ?", [matched.id])
            try session.query(
                "UPDATE core_credential_resets SET state = 'cancelled' WHERE device_id = ? AND state = 'open'",
                [CoreColumns.id(request.deviceID)])
            try Self.recordEvent(
                "credential_reset", subject: request.deviceID, detail: "the verifier was replaced", time, session)
            return .reset(deviceID: request.deviceID, at: time)
        }
    }

    // MARK: - Challenges (§8.1.5)

    /// Issues a challenge for `device` and `purpose`, kept with this run's generation and a monotonic deadline 120
    /// seconds away. Any device ID gets one; only verification asks whether its key is known.
    public func issueChallenge(device: Identifier128, purpose: ChallengePurpose) throws(CoreLedgerError) -> Challenge {
        let challengeID = Identifier128.random()
        let nonce = [UInt8](RandomTokens.bytes(Challenge.nonceBytes))
        let deadline = monotonic.now().advanced(by: .seconds(Challenge.lifetimeSeconds))
        let time = now()
        return try ledger.write { session, _ in
            let epoch = try CoreLedger.epoch(in: session)
            try session.query(
                """
                INSERT INTO core_challenges (challenge_id, nonce, purpose, device_id, epoch_id, run_generation, deadline,
                  state, issued_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)
                """,
                [
                    CoreColumns.id(challengeID), CoreColumns.bytes(nonce), .text(purpose.rawValue),
                    CoreColumns.id(device),
                    CoreColumns.id(epoch), CoreColumns.id(self.runGeneration), .integer(Int64(deadline.nanoseconds)),
                    .integer(time),
                ])
            return try Challenge(
                challengeID: challengeID, nonce: nonce, purpose: purpose, datasetID: self.ledger.datasetID,
                epochID: epoch, deviceID: device)
        }
    }

    /// Verifies a response for `body` and `purpose` in one write transaction, marking the challenge used when it
    /// verifies, or when its device has been revoked since.
    public func verifyChallenge(_ proof: ChallengeProof, body: [UInt8], purpose: ChallengePurpose)
        throws(CoreLedgerError) -> CoreChallengeVerdict
    {
        let instant = monotonic.now()
        return try ledger.write { session, _ in
            guard
                let row = try session.query(
                    """
                    SELECT nonce, purpose, device_id, epoch_id, run_generation, deadline, state
                    FROM core_challenges WHERE challenge_id = ?
                    """, [CoreColumns.id(proof.challengeID)]
                ).first
            else { return .refused(.unknown) }
            guard case .text("open") = row[6] else { return .refused(.used) }
            guard try CoreColumns.identifier(row[4]) == self.runGeneration else { return .refused(.otherRun) }
            let epoch = try CoreColumns.identifier(row[3])
            guard epoch == (try CoreLedger.epoch(in: session)) else { return .refused(.otherEpoch) }
            guard try CoreColumns.text(row[1]) == purpose.rawValue else { return .refused(.purposeMismatch) }
            guard instant.nanoseconds < UInt64(max(0, try CoreColumns.integer(row[5]))) else {
                return .refused(.expired)
            }
            let device = try CoreColumns.identifier(row[2])
            guard
                let registered = try session.query(
                    "SELECT status, operation_key FROM core_devices WHERE device_id = ?", [CoreColumns.id(device)]
                ).first
            else { return .refused(.unknownKey) }
            guard case .text("active") = registered[0] else {
                try session.query(
                    "UPDATE core_challenges SET state = 'used' WHERE challenge_id = ?",
                    [CoreColumns.id(proof.challengeID)])
                return .refused(.revokedDevice)
            }
            guard let key = try? P256Verifier(canonicalSPKI: try CoreColumns.bytes(registered[1])),
                proof.keyID == ChallengeSigning.keyID(key)
            else { return .refused(.unknownKey) }
            let challenge = try Challenge(
                challengeID: proof.challengeID, nonce: try CoreColumns.bytes(row[0]), purpose: purpose,
                datasetID: self.ledger.datasetID, epochID: epoch, deviceID: device)
            guard ChallengeSigning.isValid(proof, for: challenge, body: body, key: key) else {
                return .refused(.invalidSignature)
            }
            try session.query(
                "UPDATE core_challenges SET state = 'used' WHERE challenge_id = ?", [CoreColumns.id(proof.challengeID)])
            return .verified(deviceID: device, purpose: purpose)
        }
    }
}
