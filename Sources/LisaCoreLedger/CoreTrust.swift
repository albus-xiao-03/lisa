// Core's trust lifecycle (plan §8.1.2, §8.1.3): enrollment records and their single-use tokens, Core's device registry,
// the signed roster, revocations and device authentication. Everything shares the ledger's store and its one writer:
// an enrollment request is verified and consumed in one write transaction, and a failed attempt is committed while
// the refusal is answered. Core stores a token's hash and a credential's verifier, never the token or the credential,
// and never the request bytes, which contain the token.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaStore
import LisaSyncProtocol
import LisaTime
import LisaTrust

/// Core's enrollment, roster and device registry.
public final class CoreTrust: Sendable {
    public let ledger: CoreLedger
    public let tls: CoreTLSIdentity
    public let exportKey: P256AgreementPublicKey
    public let configuration: CoreTrustConfiguration
    /// The signed anchors bundle, in `ca` mode.
    public let anchors: SignedBody?
    /// This run's generation: a Core restart invalidates every outstanding challenge (§8.1.5).
    public let runGeneration = Identifier128.random()
    /// Challenge deadlines; a wall-clock step has no effect on them.
    let monotonic: any MonotonicClock
    let now: @Sendable () -> Int64

    /// Opens Core's trust state over `ledger`. The newest roster must carry the current pins, anchors digest, export
    /// key and policy; otherwise Core signs a new version now.
    public init(
        ledger: CoreLedger, tls: CoreTLSIdentity, exportKey: P256AgreementPublicKey,
        configuration: CoreTrustConfiguration = CoreTrustConfiguration(),
        monotonic: any MonotonicClock = BootTimeClock(),
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
    ) throws(CoreLedgerError) {
        self.ledger = ledger
        self.tls = tls
        self.exportKey = exportKey
        self.configuration = configuration
        self.monotonic = monotonic
        self.now = now
        if tls.mode == .ca, let ca = tls.caCertificate {
            do {
                anchors = try EnrollmentSigning.signAnchors(
                    TLSAnchorsBundle(datasetID: ledger.datasetID, caCertificate: ca, intermediates: tls.intermediates),
                    with: ledger.signer)
            } catch {
                throw .signingFailed("the anchors bundle")
            }
        } else {
            anchors = nil
        }
        let time = now()
        try ledger.write { session, _ in
            if let newest = try self.newestRoster(in: session),
                self.isCurrent(newest, at: time, epoch: try CoreLedger.epoch(in: session))
            {
                return
            }
            _ = try self.signRoster(in: session, time: time)
        }
    }

    /// The anchors digest the roster carries.
    var anchorsDigest: Digest256? { anchors.map { EnrollmentSigning.anchorsDigest($0) } }

    var caDigest: Digest256? { tls.caCertificate.map(Self.sha256) }

    // MARK: - Issuing enrollments (`lisa core device enroll`)

    /// Stores an open enrollment for one device and returns its owner text: shown once, never stored by Core.
    public func issueEnrollment(name: String, deviceClass: RosterDevice.DeviceClass) throws(CoreLedgerError)
        -> PairingText
    {
        guard RosterDevice.isValidName(name) else { throw .encodingFailed("the device name") }
        guard let host = URLComponents(string: tls.coreURL)?.host else { throw .encodingFailed("Core's URL") }
        let token = EnrollmentToken.random()
        let enrollmentID = Identifier128.random()
        let time = now()
        let expiresAt = time + configuration.enrollmentLifetime
        let issuer = ledger.coreKey
        let text: PairingText
        do {
            text = try PairingText(
                coreURL: tls.coreURL, trustMode: tls.mode == .ca ? .ca : .pin, leafPin: tls.servedPin,
                caDigest: caDigest, datasetID: ledger.datasetID, enrollmentID: enrollmentID, token: token,
                expiresAt: expiresAt, coreSigningKey: CoreSigningIdentity(verifier: issuer))
        } catch {
            throw .encodingFailed("the pairing text")
        }
        _ = try ledger.write { session, _ in
            try session.query(
                """
                INSERT INTO core_enrollments (enrollment_id, token_hash, issued_at, expires_at, attempts, state,
                  device_name, device_class, host, issuer_fingerprint)
                VALUES (?, ?, ?, ?, 0, 'open', ?, ?, ?, ?)
                """,
                [
                    CoreColumns.id(enrollmentID), CoreColumns.bytes(token.tokenHash), .integer(time),
                    .integer(expiresAt), .text(name), .text(deviceClass.rawValue), .text(host),
                    CoreColumns.bytes(issuer.fingerprint),
                ])
        }
        return text
    }

    /// Every enrollment, newest first.
    public func enrollments() throws(CoreLedgerError) -> [CoreEnrollmentRecord] {
        try ledger.read { session, _ in
            try session.query(
                """
                SELECT enrollment_id, state, device_name, device_class, issued_at, expires_at, attempts, device_id,
                  response IS NOT NULL
                FROM core_enrollments ORDER BY issued_at DESC, enrollment_id
                """
            ).map { row in
                guard let state = CoreEnrollmentRecord.State(rawValue: try CoreColumns.text(row[1])),
                    let deviceClass = RosterDevice.DeviceClass(rawValue: try CoreColumns.text(row[3]))
                else { throw CoreLedgerError.corrupt("an enrollment") }
                return CoreEnrollmentRecord(
                    enrollmentID: try CoreColumns.identifier(row[0]), state: state,
                    deviceName: try CoreColumns.text(row[2]), deviceClass: deviceClass,
                    issuedAt: try CoreColumns.integer(row[4]), expiresAt: try CoreColumns.integer(row[5]),
                    attempts: try CoreColumns.integer(row[6]), deviceID: try CoreColumns.optionalIdentifier(row[7]),
                    responseKept: try CoreColumns.integer(row[8]) != 0)
            }
        }
    }

    /// Cancels an open enrollment; returns whether one was open.
    @discardableResult
    public func cancelEnrollment(_ enrollmentID: Identifier128) throws(CoreLedgerError) -> Bool {
        let time = now()
        return try ledger.write { session, _ in
            try session.query(
                "UPDATE core_enrollments SET state = 'cancelled' WHERE enrollment_id = ? AND state = 'open'",
                [CoreColumns.id(enrollmentID)])
            guard session.changes == 1 else { return false }
            try Self.recordEvent("enrollment_cancelled", subject: enrollmentID, detail: "by the owner", time, session)
            return true
        }
    }

    // MARK: - Enrollment (`POST /v2/enrollments`, §8.1.2 step 5)

    /// Verifies and, if everything holds, consumes the enrollment, in one write transaction. A failed attempt is
    /// committed with the refusal; an exact retry of a consumed enrollment gets the stored response.
    public func enroll(_ wireBody: [UInt8]) throws(CoreLedgerError) -> CoreEnrollmentAnswer {
        let signed: SignedBody
        let request: EnrollmentRequest
        do {
            signed = try EnrollmentWire.request(fromBody: wireBody)
            request = try EnrollmentRequest.decode(body: signed.body)
        } catch {
            return .refused(.malformed)
        }
        let digest = EnrollmentSigning.requestDigest(signed)
        let time = now()
        return try ledger.write { session, _ in
            try self.enroll(signed, request, digest: digest, time: time, session: session)
        }
    }

    private func enroll(
        _ signed: SignedBody, _ request: EnrollmentRequest, digest: Digest256, time: Int64, session: SQLiteSession
    ) throws -> CoreEnrollmentAnswer {
        let id = request.enrollmentID
        guard
            let row = try session.query(
                """
                SELECT state, token_hash, expires_at, attempts, device_class, issuer_fingerprint, request_digest,
                  device_id, consumed_at, response, response_purged_at
                FROM core_enrollments WHERE enrollment_id = ?
                """, [CoreColumns.id(id)]
            ).first
        else { return .refused(.unknown) }
        let state = try CoreColumns.text(row[0])
        // A consumed enrollment answers before any open-enrollment check, whatever the expiry.
        if state == "consumed" {
            let deviceID = try CoreColumns.identifier(row[7])
            guard try CoreColumns.digest(row[6]) == digest else {
                try Self.recordEvent(
                    "enrollment_consumed_other_digest", subject: id,
                    detail: "a different request for a consumed enrollment",
                    time, session)
                return .refused(.consumed)
            }
            guard case .blob(let stored) = row[9] else { return .refused(.responsePurged(deviceID: deviceID)) }
            if time >= (try CoreColumns.integer(row[8])) + configuration.responseRetention {
                try Self.purgeResponse(id, time, session)
                return .refused(.responsePurged(deviceID: deviceID))
            }
            return .duplicate([UInt8](stored))
        }
        guard state == "open" else { return .refused(.invalidated) }
        guard time < (try CoreColumns.integer(row[2])) else { return .refused(.expired) }
        let issuer = try CoreColumns.bytes(row[5])
        // The issuing signer must still be Core's signer; a rotation invalidates the open record.
        guard issuer == ledger.coreKey.fingerprint else {
            try session.query(
                """
                UPDATE core_enrollments SET state = 'invalidated', invalidated_reason = 'signer_rotated'
                WHERE enrollment_id = ?
                """, [CoreColumns.id(id)])
            try Self.recordEvent("enrollment_invalidated", subject: id, detail: "signer_rotated", time, session)
            return .refused(.invalidated)
        }
        let attempts = try CoreColumns.integer(row[3])
        let presented = (try? EnrollmentToken(bytes: request.token))?.tokenHash ?? []
        guard Digests.constantTimeEquals(Data(presented), Data(try CoreColumns.bytes(row[1]))) else {
            return try failedAttempt(id, attempts: attempts, .rejected, "token_mismatch", time, session)
        }
        guard let verified = try? EnrollmentSigning.verifyRequest(signed), verified == request,
            request.datasetID == ledger.datasetID, request.issuerFingerprint.bytes == issuer,
            request.trustMode == tls.mode, tls.pins.contains(where: { $0.spkiDigest == request.leafPin }),
            request.caDigest == caDigest, request.deviceClass.rawValue == (try CoreColumns.text(row[4]))
        else { return try failedAttempt(id, attempts: attempts, .rejected, "request_invalid", time, session) }
        let active = try session.query("SELECT count(*) FROM core_devices WHERE status = 'active'").first?.first?
            .integer
        guard (active ?? 0) < Int64(configuration.maximumDevices) else {
            return try failedAttempt(id, attempts: attempts, .deviceLimit, "device_limit", time, session)
        }
        guard
            try session.query(
                "SELECT 1 FROM core_devices WHERE credential_verifier = ?",
                [CoreColumns.digest(request.credentialVerifier)]
            ).isEmpty
        else { return try failedAttempt(id, attempts: attempts, .rejected, "credential_reused", time, session) }

        // Consume: the device, the enrollment's terminal record, a new roster, the authorization and the result.
        let deviceID = Identifier128.random()
        let name =
            try session.query(
                "SELECT device_name FROM core_enrollments WHERE enrollment_id = ?", [CoreColumns.id(id)]
            ).first.map { try CoreColumns.text($0[0]) } ?? request.deviceName
        try session.query(
            """
            INSERT INTO core_devices (device_id, name, device_class, status, operation_key, export_key,
              credential_verifier, enrollment_id, incarnation_id, enrolled_at)
            VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?)
            """,
            [
                CoreColumns.id(deviceID), .text(name), .text(request.deviceClass.rawValue),
                CoreColumns.bytes(request.operationKey), CoreColumns.bytes(request.exportKey),
                CoreColumns.digest(request.credentialVerifier), CoreColumns.id(id),
                CoreColumns.id(request.incarnationID),
                .integer(time),
            ])
        try session.query(
            """
            UPDATE core_enrollments SET state = 'consumed', request_digest = ?, device_id = ?, consumed_at = ?
            WHERE enrollment_id = ?
            """, [CoreColumns.digest(digest), CoreColumns.id(deviceID), .integer(time), CoreColumns.id(id)])
        let (signedRoster, roster) = try signRoster(in: session, time: time)
        let signer = ledger.signer
        let authorization = try EnrollmentSigning.signAuthorization(
            DeviceAuthorization(
                datasetID: ledger.datasetID, epochID: roster.epochID, deviceID: deviceID,
                rosterVersion: roster.version, operationKey: request.operationKey,
                capabilities: Self.sorted(configuration.deviceCapabilities), issuedAt: time),
            with: signer)
        let result = try EnrollmentSigning.signResult(
            EnrollmentResult(
                datasetID: ledger.datasetID, enrollmentID: id, issuerFingerprint: request.issuerFingerprint,
                requestDigest: digest, deviceID: deviceID, operationKey: request.operationKey,
                exportKey: request.exportKey, rosterDigest: RosterSigning.digest(signedRoster),
                authorizationDigest: Self.sha256(authorization.body), issuedAt: time),
            with: signer)
        let response = try EnrollmentResponse(result: result, roster: signedRoster, authorization: authorization)
            .canonicalBody()
        try session.query(
            "UPDATE core_enrollments SET response = ? WHERE enrollment_id = ?",
            [CoreColumns.bytes(response), CoreColumns.id(id)])
        try Self.recordEvent("device_enrolled", subject: deviceID, detail: "enrollment \(id.hex)", time, session)
        return .enrolled(response)
    }

    /// Commits one more failed attempt; the one that reaches the maximum invalidates the enrollment.
    private func failedAttempt(
        _ id: Identifier128, attempts: Int64, _ refusal: CoreEnrollmentRefusal, _ why: String, _ time: Int64,
        _ session: SQLiteSession
    ) throws -> CoreEnrollmentAnswer {
        let count = attempts + 1
        if count >= configuration.maximumAttempts {
            try session.query(
                """
                UPDATE core_enrollments SET attempts = ?, state = 'invalidated', invalidated_reason = 'too_many_attempts'
                WHERE enrollment_id = ?
                """, [.integer(count), CoreColumns.id(id)])
            try Self.recordEvent(
                "enrollment_invalidated", subject: id, detail: "too_many_attempts (\(why))", time, session)
        } else {
            try session.query(
                "UPDATE core_enrollments SET attempts = ? WHERE enrollment_id = ?",
                [.integer(count), CoreColumns.id(id)])
            try Self.recordEvent("enrollment_attempt_failed", subject: id, detail: why, time, session)
        }
        return .refused(refusal)
    }

    /// Purges every stored response older than the retention; the compact terminal records stay. Returns how many.
    @discardableResult
    public func purgeResponses() throws(CoreLedgerError) -> Int {
        let time = now()
        return try ledger.write { session, _ in
            let due = try session.query(
                "SELECT enrollment_id FROM core_enrollments WHERE response IS NOT NULL AND consumed_at + ? <= ?",
                [.integer(configuration.responseRetention), .integer(time)])
            for row in due { try Self.purgeResponse(try CoreColumns.identifier(row[0]), time, session) }
            return due.count
        }
    }

    static func purgeResponse(_ id: Identifier128, _ time: Int64, _ session: SQLiteSession) throws {
        try session.query(
            "UPDATE core_enrollments SET response = NULL, response_purged_at = ? WHERE enrollment_id = ?",
            [.integer(time), CoreColumns.id(id)])
    }

    // MARK: - Roster (§8.1.3)

    /// The newest signed roster.
    public func currentRoster() throws(CoreLedgerError) -> SignedRoster {
        try ledger.read { session, _ in
            guard let newest = try self.newestRoster(in: session) else { throw CoreLedgerError.corrupt("no roster") }
            return newest.signed
        }
    }

    /// Signs a new roster version if the newest is older than the renewal interval or no longer current; returns
    /// the newest.
    @discardableResult
    public func renewRosterIfDue() throws(CoreLedgerError) -> SignedRoster {
        let time = now()
        return try ledger.write { session, _ in
            if let newest = try self.newestRoster(in: session),
                self.isCurrent(newest, at: time, epoch: try CoreLedger.epoch(in: session))
            {
                return newest.signed
            }
            return try self.signRoster(in: session, time: time).signed
        }
    }

    /// Whether the newest roster still describes Core: signed by the current key, in the current epoch, with the
    /// current pins, anchors digest, export key and policy, and younger than the renewal interval.
    func isCurrent(_ newest: (signed: SignedRoster, roster: TrustRoster), at time: Int64, epoch: Identifier128) -> Bool
    {
        let roster = newest.roster
        return DomainSignatures.isValid(
            newest.signed.headerSignature, over: newest.signed.headerBody, domain: .pagedArtifactHeader,
            by: ledger.coreKey)
            && roster.epochID == epoch && roster.tlsPins == tls.pins && roster.anchorsDigest == anchorsDigest
            && roster.exportKey == exportKey.spkiDER && roster.policyVersion == configuration.policyVersion
            && roster.maximumNearbyTrustAgeDays == configuration.maximumNearbyTrustAgeDays
            && time - roster.issuedAt < configuration.rosterRenewalInterval
    }

    func newestRoster(in session: SQLiteSession) throws -> (signed: SignedRoster, roster: TrustRoster)? {
        guard
            let row = try session.query("SELECT signed FROM core_rosters ORDER BY version DESC LIMIT 1").first
        else { return nil }
        let signed = try EnrollmentWire.roster(fromBody: try CoreColumns.bytes(row[0]))
        let header = try PagedArtifactHeader.decode(body: signed.headerBody)
        let pages = signed.pages.sorted { $0.index < $1.index }.map(\.bytes)
        return (signed, try TrustRoster.decode(pages: pages, header: header))
    }

    /// Signs the next roster version from the registry and the revocations, and stores it.
    func signRoster(in session: SQLiteSession, time: Int64) throws -> (signed: SignedRoster, roster: TrustRoster) {
        let epoch = try CoreLedger.epoch(in: session)
        let version = (try session.query("SELECT max(version) FROM core_rosters").first?.first?.integer ?? 0) + 1
        let capabilities = Self.sorted(configuration.deviceCapabilities)
        let devices = try session.query(
            """
            SELECT device_id, name, device_class, status, operation_key, export_key, enrolled_at
            FROM core_devices ORDER BY device_id
            """
        ).map { row in
            guard let deviceClass = RosterDevice.DeviceClass(rawValue: try CoreColumns.text(row[2])),
                let status = RosterDevice.Status(rawValue: try CoreColumns.text(row[3]))
            else { throw CoreLedgerError.corrupt("a device") }
            let deviceID = try CoreColumns.identifier(row[0])
            return try RosterDevice(
                deviceID: deviceID, name: try CoreColumns.text(row[1]), deviceClass: deviceClass, status: status,
                operationKey: try CoreColumns.bytes(row[4]), exportKey: try CoreColumns.bytes(row[5]),
                enrolledAt: try CoreColumns.integer(row[6]), capabilities: status == .active ? capabilities : [],
                previousKeys: try Self.previousKeys(of: deviceID, in: session))
        }
        let revocations = try session.query(
            "SELECT device_id, epoch_id, position, revoked_at FROM core_revocations ORDER BY device_id"
        ).map { row in
            try RosterRevocation(
                deviceID: try CoreColumns.identifier(row[0]), epochID: try CoreColumns.identifier(row[1]),
                position: try CoreColumns.integer(row[2]), revokedAt: try CoreColumns.integer(row[3]))
        }
        let roster = try TrustRoster(
            datasetID: ledger.datasetID, epochID: epoch, version: version, issuedAt: time,
            policyVersion: configuration.policyVersion,
            maximumNearbyTrustAgeDays: configuration.maximumNearbyTrustAgeDays, tlsPins: tls.pins,
            anchorsDigest: anchorsDigest, exportKey: exportKey.spkiDER, devices: devices, revocations: revocations)
        let signed: SignedRoster
        do {
            signed = try RosterSigning.sign(roster, with: ledger.signer)
        } catch {
            throw CoreLedgerError.signingFailed("the roster")
        }
        try session.query(
            "INSERT INTO core_rosters (epoch_id, version, issued_at, signed) VALUES (?, ?, ?, ?)",
            [
                CoreColumns.id(epoch), .integer(version), .integer(time),
                CoreColumns.bytes(try EnrollmentWire.rosterBody(signed)),
            ])
        return (signed, roster)
    }

    // MARK: - Devices

    /// Core's registry, by device ID.
    public func devices() throws(CoreLedgerError) -> [CoreDeviceRecord] {
        try ledger.read { session, _ in
            try session.query(
                "SELECT device_id, name, device_class, status, enrolled_at, last_seen_at FROM core_devices ORDER BY device_id"
            ).map { row in
                guard let deviceClass = RosterDevice.DeviceClass(rawValue: try CoreColumns.text(row[2])),
                    let status = RosterDevice.Status(rawValue: try CoreColumns.text(row[3]))
                else { throw CoreLedgerError.corrupt("a device") }
                return CoreDeviceRecord(
                    deviceID: try CoreColumns.identifier(row[0]), name: try CoreColumns.text(row[1]),
                    deviceClass: deviceClass, status: status, enrolledAt: try CoreColumns.integer(row[4]),
                    firstSeenAt: row[5].integer)
            }
        }
    }

    /// The device a bearer credential belongs to, if that device is active. The first success records the device as
    /// seen, so a device that never received its response stays "enrolled, never seen".
    public func authenticate(credential: String) -> Identifier128? {
        guard let credential = try? CoreCredential(bearerText: credential) else { return nil }
        let verifier = credential.verifier
        guard
            let row = try? ledger.read({ session, _ in
                try session.query(
                    "SELECT device_id, status, last_seen_at FROM core_devices WHERE credential_verifier = ?",
                    [CoreColumns.digest(verifier)]
                ).first
            }), case .text("active") = row[1], let device = try? CoreColumns.identifier(row[0])
        else { return nil }
        if case .null = row[2] {
            let time = now()
            _ = try? ledger.write { session, _ in
                try session.query(
                    "UPDATE core_devices SET last_seen_at = ? WHERE device_id = ? AND last_seen_at IS NULL",
                    [.integer(time), CoreColumns.id(device)])
            }
        }
        return device
    }

    /// An active device's operation key; none for an unknown or revoked device, so intake refuses its operations
    /// whatever time they claim.
    public func operationKey(of device: Identifier128) -> P256Verifier? {
        guard
            let row = try? ledger.read({ session, _ in
                try session.query(
                    "SELECT operation_key FROM core_devices WHERE device_id = ? AND status = 'active'",
                    [CoreColumns.id(device)]
                ).first
            }), let der = try? CoreColumns.bytes(row[0])
        else { return nil }
        return try? P256Verifier(canonicalSPKI: der)
    }

    /// Revokes a device (`lisa core device revoke`): marks it revoked, records the permanent revocation at the
    /// current epoch and position, cancels its open resets, and signs a new roster. Committed data stays. A challenge
    /// it answers afterwards is refused as revoked, so its upload can be quarantined (§8.1.5). Returns the new roster,
    /// or nil for an unknown device; revoking twice changes nothing.
    @discardableResult
    public func revoke(_ device: Identifier128) throws(CoreLedgerError) -> SignedRoster? {
        let time = now()
        return try ledger.write { session, _ in
            guard
                let row = try session.query(
                    "SELECT status FROM core_devices WHERE device_id = ?", [CoreColumns.id(device)]
                ).first
            else { return nil }
            if case .text("revoked") = row[0] { return try self.newestRoster(in: session)?.signed }
            guard
                let dataset = try session.query(
                    "SELECT epoch_id, last_position FROM core_dataset WHERE singleton = 1"
                ).first
            else { throw CoreLedgerError.corrupt("the dataset row") }
            try session.query(
                "UPDATE core_devices SET status = 'revoked', revoked_at = ? WHERE device_id = ?",
                [.integer(time), CoreColumns.id(device)])
            try session.query(
                "INSERT OR IGNORE INTO core_revocations (device_id, epoch_id, position, revoked_at) VALUES (?, ?, ?, ?)",
                [CoreColumns.id(device), dataset[0], dataset[1], .integer(time)])
            try session.query(
                "UPDATE core_credential_resets SET state = 'cancelled' WHERE device_id = ? AND state = 'open'",
                [CoreColumns.id(device)])
            try Self.recordEvent("device_revoked", subject: device, detail: "by the owner", time, session)
            return try self.signRoster(in: session, time: time).signed
        }
    }

    // MARK: - Events

    public func trustEvents() throws(CoreLedgerError) -> [CoreTrustEvent] {
        try ledger.read { session, _ in
            try session.query("SELECT kind, subject, detail, recorded_at FROM core_trust_events ORDER BY event_id").map
            {
                row in
                CoreTrustEvent(
                    kind: try CoreColumns.text(row[0]), subject: try CoreColumns.optionalIdentifier(row[1]),
                    detail: try CoreColumns.text(row[2]), recordedAt: try CoreColumns.integer(row[3]))
            }
        }
    }

    static func recordEvent(
        _ kind: String, subject: Identifier128?, detail: String, _ time: Int64, _ session: SQLiteSession
    ) throws {
        try session.query(
            "INSERT INTO core_trust_events (kind, subject, detail, recorded_at) VALUES (?, ?, ?, ?)",
            [.text(kind), CoreColumns.optionalID(subject), .text(detail), .integer(time)])
    }

    static func sha256(_ bytes: [UInt8]) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(bytes))))
    }

    static func sorted(_ capabilities: [String]) -> [String] { Array(Set(capabilities)).sorted() }
}
