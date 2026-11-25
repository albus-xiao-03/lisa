// The device's trust in Core (plan §8.1.2 step 6, §8.1.3): the durable completion of an enrollment, which binds the
// request digest to the verified device, the Core signing key from the owner text and the TLS policy, and the newest
// verified roster. Completion is one write transaction, so the app never sees a partly installed enrollment, and
// repeating it with the same request digest changes nothing. A roster is accepted only when the trusted Core key
// verifies it as a whole and it is newer than the one held; its revocations are recorded first (the union rule).

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// What a verified enrollment installs.
public struct EnrollmentCompletion: Hashable, Sendable {
    public let datasetID: Identifier128
    public let deviceID: Identifier128
    public let enrollmentID: Identifier128
    /// SHA-256 of the exact signed request body the verified result binds.
    public let requestDigest: Digest256
    public let coreURL: String
    /// The Core signing key from the owner text: canonical SubjectPublicKeyInfo DER.
    public let coreSigningKey: [UInt8]
    public let tlsMode: CoreTLSMode
    public let tlsHost: String
    public let caCertificate: [UInt8]?
    public let intermediates: [[UInt8]]
    public let roster: SignedRoster

    public init(
        datasetID: Identifier128, deviceID: Identifier128, enrollmentID: Identifier128, requestDigest: Digest256,
        coreURL: String, coreSigningKey: [UInt8], tlsMode: CoreTLSMode, tlsHost: String, caCertificate: [UInt8]?,
        intermediates: [[UInt8]], roster: SignedRoster
    ) {
        self.datasetID = datasetID
        self.deviceID = deviceID
        self.enrollmentID = enrollmentID
        self.requestDigest = requestDigest
        self.coreURL = coreURL
        self.coreSigningKey = coreSigningKey
        self.tlsMode = tlsMode
        self.tlsHost = tlsHost
        self.caCertificate = caCertificate
        self.intermediates = intermediates
        self.roster = roster
    }
}

/// The Core this device trusts and how it reaches it.
public struct ReplicaTrustState: Hashable, Sendable {
    public let coreURL: String
    public let coreKey: P256Verifier
    public let tlsMode: CoreTLSMode
    public let tlsHost: String
    public let caCertificate: [UInt8]?
    public let intermediates: [[UInt8]]
    public let enrollmentID: Identifier128
    public let requestDigest: Digest256
    public let deviceID: Identifier128
    public let completedAt: Int64
}

extension ReplicaStore {
    /// Publishes a verified enrollment in one transaction: the dataset and device ID, the trust state and the roster.
    /// Returns false when this exact enrollment (the same request digest) is already complete.
    @discardableResult
    public func completeEnrollment(_ completion: EnrollmentCompletion) throws(ReplicaStoreError) -> Bool {
        let coreKey: P256Verifier
        do {
            coreKey = try P256Verifier(canonicalSPKI: completion.coreSigningKey)
        } catch {
            throw .trustMismatch
        }
        let roster: TrustRoster
        do {
            roster = try RosterSigning.verify(completion.roster, dataset: completion.datasetID, coreKey: coreKey)
        } catch {
            throw .unverifiedRoster(error)
        }
        guard roster.device(completion.deviceID)?.status == .active else { throw .trustMismatch }
        let intermediates = try Self.encodeIntermediates(completion.intermediates)
        let rosterBytes: [UInt8]
        do {
            rosterBytes = try EnrollmentWire.rosterBody(completion.roster)
        } catch {
            throw .invalidCommand(error)
        }
        let time = now()
        return try write { session in
            if let row = try session.query("SELECT request_digest FROM trust_state WHERE singleton = 1").first,
                try ReplicaColumns.digest(row[0]) == completion.requestDigest
            {
                return false
            }
            let identity = try session.query("SELECT dataset_id FROM replica_identity WHERE singleton = 1").first
            if let identity, let existing = try ReplicaColumns.optionalIdentifier(identity[0]),
                existing != completion.datasetID
            {
                throw ReplicaStoreError.datasetMismatch
            }
            try session.query(
                "UPDATE replica_identity SET dataset_id = ?, device_id = ? WHERE singleton = 1",
                [ReplicaColumns.id(completion.datasetID), ReplicaColumns.id(completion.deviceID)])
            try session.query(
                """
                INSERT OR REPLACE INTO trust_state (singleton, core_url, core_signing_key, tls_mode, tls_host,
                  ca_certificate, intermediates, enrollment_id, request_digest, device_id, completed_at)
                VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(completion.coreURL), ReplicaColumns.bytes(completion.coreSigningKey),
                    .text(completion.tlsMode.rawValue), .text(completion.tlsHost),
                    ReplicaColumns.optionalBytes(completion.caCertificate), ReplicaColumns.bytes(intermediates),
                    ReplicaColumns.id(completion.enrollmentID), ReplicaColumns.digest(completion.requestDigest),
                    ReplicaColumns.id(completion.deviceID), .integer(time),
                ])
            try session.query(
                "INSERT OR IGNORE INTO trust_rosters (epoch_id, version, signed, verified_at) VALUES (?, ?, ?, ?)",
                [
                    ReplicaColumns.id(roster.epochID), .integer(roster.version), ReplicaColumns.bytes(rosterBytes),
                    .integer(time),
                ])
            return true
        }
    }

    /// The trust this device holds, once enrolled.
    public func trustState() throws(ReplicaStoreError) -> ReplicaTrustState? {
        try read { session in
            guard
                let row = try session.query(
                    """
                    SELECT core_url, core_signing_key, tls_mode, tls_host, ca_certificate, intermediates, enrollment_id,
                      request_digest, device_id, completed_at
                    FROM trust_state WHERE singleton = 1
                    """
                ).first
            else { return nil }
            guard let mode = CoreTLSMode(rawValue: try ReplicaColumns.text(row[2])),
                let key = try? P256Verifier(canonicalSPKI: try ReplicaColumns.bytes(row[1]))
            else { throw ReplicaStoreError.corrupt("the trust state") }
            return ReplicaTrustState(
                coreURL: try ReplicaColumns.text(row[0]), coreKey: key, tlsMode: mode,
                tlsHost: try ReplicaColumns.text(row[3]), caCertificate: ReplicaColumns.optionalBytes(row[4]),
                intermediates: try Self.decodeIntermediates(try ReplicaColumns.bytes(row[5])),
                enrollmentID: try ReplicaColumns.identifier(row[6]), requestDigest: try ReplicaColumns.digest(row[7]),
                deviceID: try ReplicaColumns.identifier(row[8]), completedAt: try ReplicaColumns.integer(row[9]))
        }
    }

    /// The newest verified roster, as it travels and decoded.
    public func newestRoster() throws(ReplicaStoreError) -> (signed: SignedRoster, roster: TrustRoster)? {
        try read { session in
            guard
                let row = try session.query("SELECT signed FROM trust_rosters ORDER BY version DESC LIMIT 1").first
            else { return nil }
            let signed = try EnrollmentWire.roster(fromBody: try ReplicaColumns.bytes(row[0]))
            let header = try PagedArtifactHeader.decode(body: signed.headerBody)
            let pages = signed.pages.sorted { $0.index < $1.index }.map(\.bytes)
            return (signed, try TrustRoster.decode(pages: pages, header: header))
        }
    }

    /// Accepts a roster from Core or a peer: verified by the trusted Core key as a whole, and newer than the one
    /// held. Its revocations are recorded first, so an interruption can't keep the new roster without them.
    @discardableResult
    public func acceptRoster(_ signed: SignedRoster) throws(ReplicaStoreError) -> TrustRoster {
        guard let keys = try keyHistory() else { throw .notEnrolled }
        let held = try newestRoster()?.roster
        let datasetID = keys.datasetID
        let roster: TrustRoster
        do {
            roster = try RosterSigning.verifyNewer(signed, than: held, dataset: datasetID, coreKey: keys.current)
        } catch {
            throw .unverifiedRoster(error)
        }
        for revocation in roster.revocations {
            try recordRevocation(
                device: revocation.deviceID, epochID: revocation.epochID, position: revocation.position)
        }
        let bytes: [UInt8]
        do {
            bytes = try EnrollmentWire.rosterBody(signed)
        } catch {
            throw .invalidCommand(error)
        }
        let time = now()
        _ = try write { session in
            try session.query(
                "INSERT OR IGNORE INTO trust_rosters (epoch_id, version, signed, verified_at) VALUES (?, ?, ?, ?)",
                [
                    ReplicaColumns.id(roster.epochID), .integer(roster.version), ReplicaColumns.bytes(bytes),
                    .integer(time),
                ])
        }
        return roster
    }

    // MARK: - Core's key history (§8.1.4)

    /// The key history this device trusts: the owner text's key, then every transition verified since.
    public func keyHistory() throws(ReplicaStoreError) -> CoreKeyHistory? {
        guard let trust = try trustState(), let dataset = try identity().datasetID else { return nil }
        let transitions = try read { session in
            try session.query(
                "SELECT body, previous_signature, next_signature FROM trust_key_transitions ORDER BY sequence"
            ).map { row in
                try SignedKeyTransition(
                    body: try ReplicaColumns.bytes(row[0]), previousSignature: try ReplicaColumns.bytes(row[1]),
                    nextSignature: try ReplicaColumns.bytes(row[2]))
            }
        }
        do {
            return try CoreKeyHistory(datasetID: dataset, anchor: trust.coreKey).applying(all: transitions)
        } catch {
            throw .corrupt("the key history: \(error)")
        }
    }

    /// Takes Core's transitions, verified against the history this device holds (each new one signed by both of its
    /// keys, from the current key, the next in sequence; those from before the owner text's key skipped), and keeps
    /// them, so the history rebuilds the same way. Returns the history.
    @discardableResult
    public func acceptKeyTransitions(_ transitions: [SignedKeyTransition]) throws(ReplicaStoreError) -> CoreKeyHistory {
        guard let held = try keyHistory() else { throw .notEnrolled }
        let updated: CoreKeyHistory
        do {
            updated = try held.applying(all: transitions)
        } catch {
            throw .unverifiedKeyTransition(error)
        }
        guard updated != held else { return held }
        var fresh: [(sequence: Int64, signed: SignedKeyTransition)] = []
        for signed in transitions {
            if let sequence = try? signed.transition().sequence { fresh.append((sequence, signed)) }
        }
        let time = now()
        _ = try write { session in
            for item in fresh {
                try session.query(
                    """
                    INSERT OR IGNORE INTO trust_key_transitions (sequence, body, previous_signature, next_signature,
                      verified_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    [
                        .integer(item.sequence), ReplicaColumns.bytes(item.signed.body),
                        ReplicaColumns.bytes(item.signed.previousSignature),
                        ReplicaColumns.bytes(item.signed.nextSignature), .integer(time),
                    ])
            }
        }
        return updated
    }

    /// Records a Core receipt after verifying it by the key history: a final receipt by the key valid at its commit
    /// position, a provisional one by any key of the history (§8.1.4).
    @discardableResult
    public func recordReceipt(_ signed: SignedCoreReceipt, keys: CoreKeyHistory) throws(ReplicaStoreError) -> Bool {
        guard let datasetID = try identity().datasetID, datasetID == keys.datasetID else { throw .notEnrolled }
        let receipt: CoreReceipt
        do {
            receipt = try keys.verifyReceipt(signed)
        } catch {
            throw .unverifiedReceipt(error)
        }
        let status: ReplicaReceipt.Status =
            switch receipt.outcome {
            case .waitingForDependencies: .waitingForDependencies
            case .accepted: .accepted
            case .acceptedWithConflict: .acceptedWithConflict
            case .rejected: .rejected
            }
        return try recordReceipt(
            ReplicaReceipt(
                operationID: receipt.operationID, digest: receipt.digest, status: status,
                epochID: receipt.position == nil ? nil : receipt.epochID, position: receipt.position,
                signedBytes: signed.storedBytes))
    }

    /// The operation key of a device in the newest verified roster; none for an unknown or revoked device.
    public func rosterKey(of device: Identifier128) throws(ReplicaStoreError) -> P256Verifier? {
        guard let roster = try newestRoster()?.roster, let entry = roster.device(device), entry.status == .active,
            !roster.isRevoked(device)
        else { return nil }
        return try? P256Verifier(canonicalSPKI: entry.operationKey)
    }

    static func encodeIntermediates(_ intermediates: [[UInt8]]) throws(ReplicaStoreError) -> [UInt8] {
        do {
            return try CanonicalEncoder.encode(
                .array(intermediates.map { .string(StrictBase64URL.encode($0)) }),
                limits: CanonicalLimits(maxBytes: 262_144))
        } catch {
            throw .invalidCommand(.encoding(error))
        }
    }

    static func decodeIntermediates(_ bytes: [UInt8]) throws -> [[UInt8]] {
        guard case .array(let values) = try CanonicalDecoder.decode(bytes, limits: CanonicalLimits(maxBytes: 262_144))
        else { throw ReplicaStoreError.corrupt("the trust state's intermediates") }
        return try values.map { value in
            guard case .string(let text) = value, let der = try? StrictBase64URL.decode(text) else {
                throw ReplicaStoreError.corrupt("the trust state's intermediates")
            }
            return der
        }
    }
}
