// Core's signing-key history and rotation (plan §8.1.4, §8.5.3). Rotating records, in one write transaction, a
// transition signed by the current and the next key, activating at the next commit position: the current key signs
// every position before it and the next key every position from it. The rotating ledger's signer is retired at once,
// so it signs nothing more; Core restarts with the next key's private half, and opening checks that the signer is the
// history's current key. On a fresh host the same check accepts the restored current key and refuses a retired or an
// unknown one; `importKeyTransition` appends a verified transition to a stopped store (`lisa core trust import-key`).

import Foundation
import LisaCrypto
import LisaSQLite
import LisaStore
import LisaSyncProtocol
import LisaTrust

/// A signing key that stops signing once retired.
final class RetirableSigner: MessageSigning, @unchecked Sendable {
    private let wrapped: any MessageSigning
    private let lock = NSLock()
    private var retired = false

    init(_ signer: any MessageSigning) {
        wrapped = signer
    }

    var verifier: P256Verifier { wrapped.verifier }

    var isRetired: Bool { lock.withLock { retired } }

    func retire() { lock.withLock { retired = true } }

    func rawSignature(for message: [UInt8]) throws -> [UInt8] {
        guard !isRetired else { throw CoreLedgerError.signerRetired }
        return try wrapped.rawSignature(for: message)
    }
}

extension CoreLedger {
    /// Rotates Core's signing key to `next`: the transition, signed by the current key and by `next`, activates at the
    /// next commit position. This ledger's signer is then retired; open a new ledger with `next` to continue. Refused
    /// when nothing has been committed since the last rotation, so every key signs at least one position.
    public func rotateSigningKey(to next: any MessageSigning) throws(CoreLedgerError) -> SignedKeyTransition {
        guard !signer.isRetired else { throw .signerRetired }
        let time = now()
        let signed = try write { session, _ -> SignedKeyTransition in
            guard
                let current = try session.query(
                    "SELECT sequence, signing_key, valid_from FROM core_signing_keys ORDER BY sequence DESC LIMIT 1"
                ).first,
                let head = try session.query("SELECT last_position FROM core_dataset WHERE singleton = 1").first
            else { throw CoreLedgerError.corrupt("the key history") }
            guard try CoreColumns.bytes(current[1]) == self.signer.verifier.spkiDER else {
                throw CoreLedgerError.signerRetired
            }
            let sequence = try CoreColumns.integer(current[0]) + 1
            let activation = try CoreColumns.integer(head[0]) + 1
            guard activation > (try CoreColumns.integer(current[2])) else {
                throw CoreLedgerError.keyHistory("nothing was committed since the last rotation")
            }
            let transition = try SigningKeyTransition(
                datasetID: self.datasetID, sequence: sequence, previousKey: self.signer.verifier.spkiDER,
                nextKey: next.verifier.spkiDER, activationPosition: activation, issuedAt: time)
            let signed: SignedKeyTransition
            do {
                signed = try KeyTransitionSigning.sign(transition, previous: self.signer, next: next)
            } catch {
                throw CoreLedgerError.signingFailed("the key transition")
            }
            try Self.append(signed, transition, time, session)
            return signed
        }
        signer.retire()
        return signed
    }

    /// Every transition, in sequence order: what `GET /v2/trust` carries beside the roster.
    public func keyTransitions() throws(CoreLedgerError) -> [SignedKeyTransition] {
        try read { session, _ in try Self.transitions(in: session) }
    }

    /// The verified history: the anchor and every transition.
    public func keyHistory() throws(CoreLedgerError) -> CoreKeyHistory {
        try read { session, _ in try Self.history(in: session, dataset: self.datasetID) }
    }

    /// Appends a verified transition to a store no ledger has open (`lisa core trust import-key`): it must continue
    /// the store's history (signed by both keys, from its current key, the next in sequence), and the store must have
    /// reached its activation position, so the next key signs only positions it owns. A transition already recorded
    /// changes nothing. Then open a ledger with the next key's private half.
    public static func importKeyTransition(_ signed: SignedKeyTransition, into storage: LisaStorage)
        throws(CoreLedgerError)
    {
        do {
            try storage.records.ledgerWrite { session, _ in
                guard
                    let dataset = try session.query(
                        "SELECT dataset_id, last_position FROM core_dataset WHERE singleton = 1"
                    ).first
                else { throw CoreLedgerError.corrupt("the dataset row") }
                let history = try history(in: session, dataset: try CoreColumns.identifier(dataset[0]))
                let transition = try signed.transition()
                let updated: CoreKeyHistory
                do {
                    updated = try history.applying(all: [signed])
                } catch {
                    throw CoreLedgerError.keyHistory(String(describing: error))
                }
                guard updated.transitionCount > history.transitionCount else { return }
                guard transition.activationPosition <= (try CoreColumns.integer(dataset[1])) + 1 else {
                    throw CoreLedgerError.keyHistory(
                        "the store is behind the activation position \(transition.activationPosition)")
                }
                try append(signed, transition, Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)), session)
            }
        } catch {
            throw CoreLedgerError.classify(error)
        }
    }

    static func append(
        _ signed: SignedKeyTransition, _ transition: SigningKeyTransition, _ time: Int64, _ session: SQLiteSession
    ) throws {
        try session.query(
            "UPDATE core_signing_keys SET retired_at = ? WHERE sequence = ?",
            [.integer(transition.activationPosition), .integer(transition.sequence - 1)])
        try session.query(
            """
            INSERT INTO core_signing_keys (sequence, signing_key, valid_from, transition_body, previous_signature,
              next_signature, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .integer(transition.sequence), CoreColumns.bytes(transition.nextKey),
                .integer(transition.activationPosition), CoreColumns.bytes(signed.body),
                CoreColumns.bytes(signed.previousSignature), CoreColumns.bytes(signed.nextSignature), .integer(time),
            ])
    }

    static func transitions(in session: SQLiteSession) throws -> [SignedKeyTransition] {
        try session.query(
            """
            SELECT transition_body, previous_signature, next_signature FROM core_signing_keys
            WHERE sequence > 0 ORDER BY sequence
            """
        ).map { row in
            try SignedKeyTransition(
                body: try CoreColumns.bytes(row[0]), previousSignature: try CoreColumns.bytes(row[1]),
                nextSignature: try CoreColumns.bytes(row[2]))
        }
    }

    static func history(in session: SQLiteSession, dataset: Identifier128) throws -> CoreKeyHistory {
        guard
            let anchor = try session.query("SELECT signing_key FROM core_signing_keys WHERE sequence = 0").first,
            let key = try? P256Verifier(canonicalSPKI: try CoreColumns.bytes(anchor[0]))
        else { throw CoreLedgerError.corrupt("the key history's anchor") }
        do {
            return try CoreKeyHistory(datasetID: dataset, anchor: key, sequence: 0).applying(
                all: try transitions(in: session))
        } catch let error as KeyHistoryError {
            throw CoreLedgerError.corrupt("the key history: \(error)")
        }
    }
}
