// The Core ledger (plan §8.4.1, §8.2.1, §8.2.2, §8.4.2). Intake runs in one write transaction with a savepoint per
// operation: dataset and epoch; origin, signature and digest; the duplicate rules with no exception; authorization by
// the roster's keys; dependencies, whose release is queued in bounded steps; merge and the projection into R1's
// records; the change-log entry, the operation record (also the idempotency record) and the receipt. Core signs every
// receipt and change page. M3-1 applies the task family (task.*, notes, tags, deletion, conflict resolution) to
// tasks; other operation types are refused as unsupported until their milestones add them.

import Foundation
import LisaCrypto
import LisaDomain
import LisaMerge
import LisaPorts
import LisaSQLite
import LisaStore
import LisaSyncProtocol
import LisaTrust

/// What intake did with one operation.
public enum CoreIntakeOutcome: Hashable, Sendable {
    /// Decided now (a final receipt) or held for its dependencies (a provisional receipt).
    case receipted(SignedCoreReceipt)
    /// The same ID and digest as a known operation: its current receipt.
    case duplicate(SignedCoreReceipt)
    /// The same ID with another digest: refused, with a security event.
    case rejectedIdentityReuse
    /// The same origin triple under another ID: refused, with a security event.
    case rejectedSequenceReuse
    /// Not verified (dataset, origin key, signature or envelope): refused before anything was stored; no receipt.
    case unverified(OperationVerificationError)
}

/// One release step's work.
public enum CoreReleaseStep: Hashable, Sendable {
    case expanded(edges: Int, enqueued: Int)
    case released([Identifier128])
    case idle
}

/// The dataset, epoch and newest commit position.
public struct CoreLedgerStatus: Hashable, Sendable {
    public let datasetID: Identifier128
    public let epochID: Identifier128
    public let lastPosition: Int64
}

/// Core's operation ledger over R1's store.
public final class CoreLedger: Sendable {
    public let storage: LisaStorage
    public let datasetID: Identifier128
    let signer: any MessageSigning
    private let now: @Sendable () -> Int64

    /// The origin key of Core's own operations in round-robin release.
    // Sixteen bytes always make an identifier.
    static let coreOrigin = try! Identifier128(bytes: [UInt8](repeating: 0, count: 16))

    /// The verification key of Core's receipts and pages.
    public var coreKey: P256Verifier { signer.verifier }

    /// Opens the ledger of `datasetID` in `storage`, starting it in `newEpochID` when the store holds none yet.
    /// - Parameter now: Unix milliseconds, for receive and commit times; never used to order operations.
    public init(
        storage: LisaStorage, signer: any MessageSigning, datasetID: Identifier128, newEpochID: Identifier128,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
    ) throws(CoreLedgerError) {
        self.storage = storage
        self.signer = signer
        self.datasetID = datasetID
        self.now = now
        let time = now()
        try write { session, _ in
            if let row = try session.query("SELECT dataset_id FROM core_dataset WHERE singleton = 1").first {
                guard try CoreColumns.identifier(row[0]) == datasetID else { throw CoreLedgerError.datasetMismatch }
            } else {
                try session.query(
                    """
                    INSERT INTO core_dataset (singleton, dataset_id, epoch_id, recovery_state, last_position, created_at)
                    VALUES (1, ?, ?, 'normal', 0, ?)
                    """, [CoreColumns.id(datasetID), CoreColumns.id(newEpochID), .integer(time)])
            }
        }
    }

    public func status() throws(CoreLedgerError) -> CoreLedgerStatus {
        try read { session, _ in
            guard
                let row = try session.query(
                    "SELECT dataset_id, epoch_id, last_position FROM core_dataset WHERE singleton = 1"
                ).first
            else { throw CoreLedgerError.corrupt("the dataset row") }
            return CoreLedgerStatus(
                datasetID: try CoreColumns.identifier(row[0]), epochID: try CoreColumns.identifier(row[1]),
                lastPosition: try CoreColumns.integer(row[2]))
        }
    }

    // MARK: - Intake (§8.4.1)

    /// Takes in a batch of signed operations in one write transaction, one outcome each, in order. `deviceKey` gives
    /// each enrolled device's key from the roster; an unknown device's operation is unverified.
    public func intake(_ operations: [SignedOperation], deviceKey: (Identifier128) -> P256Verifier?)
        throws(CoreLedgerError) -> [CoreIntakeOutcome]
    {
        var outcomes = [CoreIntakeOutcome?](repeating: nil, count: operations.count)
        var verified: [(index: Int, operation: SignedOperation, envelope: OperationEnvelope)] = []
        for (index, operation) in operations.enumerated() {
            do {
                let envelope = try OperationSigning.verify(
                    operation, dataset: datasetID, deviceKey: deviceKey, coreKey: signer.verifier)
                verified.append((index, operation, envelope))
            } catch {
                outcomes[index] = .unverified(error)
            }
        }
        let time = now()
        try write { session, records in
            let epoch = try Self.epoch(in: session)
            for item in verified {
                try session.execute("SAVEPOINT intake")
                do {
                    outcomes[item.index] = try self.intakeOne(
                        item.operation, envelope: item.envelope, epoch: epoch, time: time, session: session,
                        records: records)
                    try session.execute("RELEASE intake")
                } catch {
                    try? session.execute("ROLLBACK TO intake")
                    try? session.execute("RELEASE intake")
                    throw error
                }
            }
        }
        return outcomes.map { $0 ?? .unverified(.malformed(.invalidField("intake"))) }
    }

    private func intakeOne(
        _ operation: SignedOperation, envelope: OperationEnvelope, epoch: Identifier128, time: Int64,
        session: SQLiteSession, records: any RecordWriting
    ) throws -> CoreIntakeOutcome {
        let digest = OperationDigest.of(body: operation.body)
        let byID = try CoreOperationRecords.known(byID: envelope.operationID, in: session)
        let byOrigin = try envelope.origin.deviceTriple.flatMap { triple in
            try CoreOperationRecords.known(
                byOrigin: OriginTriple(
                    device: triple.device, incarnation: triple.incarnation, sequence: triple.sequence),
                in: session)
        }
        switch OperationIdentityCheck.verdict(
            arrivingID: envelope.operationID, arrivingDigest: digest, byID: byID, byOrigin: byOrigin)
        {
        case .duplicate:
            guard let stored = try CoreOperationRecords.receipt(envelope.operationID, in: session) else {
                throw CoreLedgerError.corrupt("a known operation without a receipt")
            }
            return .duplicate(try SignedCoreReceipt(storedBytes: stored))
        case .identityReuse:
            guard let byID else { throw CoreLedgerError.corrupt("identity reuse without an operation") }
            try CoreOperationRecords.recordSecurityEvent(
                .identityReuse, operationID: envelope.operationID, arrivingDigest: digest, known: byID, at: time,
                in: session)
            return .rejectedIdentityReuse
        case .sequenceReuse:
            guard let byOrigin else { throw CoreLedgerError.corrupt("sequence reuse without an operation") }
            try CoreOperationRecords.recordSecurityEvent(
                .sequenceReuse, operationID: envelope.operationID, arrivingDigest: digest, known: byOrigin, at: time,
                in: session)
            return .rejectedSequenceReuse
        case .new:
            break
        }
        try CoreOperationRecords.insertWaiting(
            operation, envelope: envelope, digest: digest, epoch: epoch, receivedAt: time, in: session)
        guard Self.isSupported(envelope) else {
            return .receipted(
                try reject(
                    envelope, digest: digest, reason: "unsupported_operation",
                    hint: "this Core doesn't apply \(envelope.operationType) to \(envelope.entityType) yet",
                    epoch: epoch,
                    session: session))
        }
        do {
            try Self.checkPayload(envelope)
        } catch {
            return .receipted(
                try reject(
                    envelope, digest: digest, reason: "malformed", hint: "the payload doesn't follow its schema",
                    epoch: epoch, session: session))
        }
        let origin = envelope.origin.deviceTriple?.device ?? Self.coreOrigin
        switch try CoreCausalTables.intake(
            envelope.operationID, origin: origin, dependencies: envelope.dependencies, in: session)
        {
        case .rejectedMalformed:
            return .receipted(
                try reject(
                    envelope, digest: digest, reason: "malformed", hint: "an operation names at most 32 dependencies",
                    epoch: epoch, session: session))
        case .rejectedCycle(let members):
            var own: SignedCoreReceipt?
            for member in members.sorted(by: { $0.bytes.lexicographicallyPrecedes($1.bytes) }) {
                guard let stored = try CoreOperationRecords.operation(member, in: session) else { continue }
                let receipt = try reject(
                    try OperationEnvelope.decode(body: stored.body), digest: OperationDigest.of(body: stored.body),
                    reason: "dependency_cycle", hint: nil, epoch: epoch, session: session)
                if member == envelope.operationID { own = receipt }
            }
            guard let own else { throw CoreLedgerError.corrupt("a cycle without the arriving operation") }
            return .receipted(own)
        case .waiting(let missing):
            let receipt = try sign(
                try CoreReceipt(
                    datasetID: datasetID, epochID: epoch, operationID: envelope.operationID, digest: digest,
                    outcome: .waitingForDependencies, position: nil, missing: missing))
            try CoreOperationRecords.setReceipt(envelope.operationID, receipt, in: session)
            return .receipted(receipt)
        case .ready:
            return .receipted(
                try apply(envelope, digest: digest, epoch: epoch, time: time, session: session, records: records))
        }
    }

    /// Applies a ready operation at the next commit position: merge, projection, change log, final receipt.
    private func apply(
        _ envelope: OperationEnvelope, digest: Digest256, epoch: Identifier128, time: Int64, session: SQLiteSession,
        records: any RecordWriting
    ) throws -> SignedCoreReceipt {
        let payload = try ItemOperationPayload(operationType: envelope.operationType, payload: envelope.payload)
        var isCreation = false
        if case .taskCreate = payload { isCreation = true }
        // §8.2.2: on an item Core never held, only its creation applies; anything else is rejected, as
        // `dependency_rejected` when a dependency was.
        if !isCreation, try !CoreOperationRecords.hasAccepted(envelope.entityType, envelope.entityID, in: session) {
            var dependencyRejected = false
            for dependency in envelope.dependencies
            where try CoreCausalTables.decision(dependency, in: session) == .rejected {
                dependencyRejected = true
            }
            return try reject(
                envelope, digest: digest, reason: dependencyRejected ? "dependency_rejected" : "unknown_item",
                hint: "the item doesn't exist on Core", epoch: epoch, session: session)
        }
        let position = try Self.nextPosition(in: session)
        try CoreOperationRecords.decide(
            envelope.operationID, state: "accepted", reason: nil, position: position, in: session)
        let view = try CoreTaskFold.view(envelope.entityID, in: session)
        let conflict = view.map { CoreTaskFold.leavesConflict(payload, in: $0) } ?? false
        if conflict {
            try CoreOperationRecords.decide(
                envelope.operationID, state: "accepted_with_conflict", reason: nil, position: position, in: session)
        }
        if case .itemDelete = payload {
            try session.query(
                "INSERT OR IGNORE INTO core_tombstones (entity_type, entity_id, position) VALUES (?, ?, ?)",
                [.text(envelope.entityType), CoreColumns.id(envelope.entityID), .integer(position)])
        }
        let created = try CoreOperationRecords.creationTime(of: envelope.entityID, in: session).map {
            Date(timeIntervalSince1970: Double($0) / 1_000)
        }
        try TaskProjection.project(
            view, entityID: envelope.entityID, createdAt: created,
            commitTime: Date(timeIntervalSince1970: Double(time) / 1_000), into: records)
        try Self.logChange(
            position, envelope.operationID, decision: conflict ? .acceptedWithConflict : .accepted, epoch: epoch,
            partition: CoreTaskFold.partition, in: session)
        let receipt = try sign(
            try CoreReceipt(
                datasetID: datasetID, epochID: epoch, operationID: envelope.operationID, digest: digest,
                outcome: conflict ? .acceptedWithConflict : .accepted, position: position))
        try CoreOperationRecords.setReceipt(envelope.operationID, receipt, in: session)
        try CoreCausalTables.decide(envelope.operationID, .applied, in: session)
        return receipt
    }

    /// Rejects a stored operation at the next commit position: the change log carries the decision too.
    private func reject(
        _ envelope: OperationEnvelope, digest: Digest256, reason: String, hint: String?, epoch: Identifier128,
        session: SQLiteSession
    ) throws -> SignedCoreReceipt {
        let position = try Self.nextPosition(in: session)
        try CoreOperationRecords.decide(
            envelope.operationID, state: "rejected", reason: reason, position: position, in: session)
        try Self.logChange(
            position, envelope.operationID, decision: .rejected, epoch: epoch,
            partition: CollectionPartition.name(forEntityType: envelope.entityType) ?? envelope.entityType,
            in: session)
        let receipt = try sign(
            try CoreReceipt(
                datasetID: datasetID, epochID: epoch, operationID: envelope.operationID, digest: digest,
                outcome: .rejected, position: position, reason: reason, recoveryHint: hint))
        try CoreOperationRecords.setReceipt(envelope.operationID, receipt, in: session)
        try CoreCausalTables.decide(envelope.operationID, .rejected, in: session)
        return receipt
    }

    // MARK: - Release (§8.2.2)

    /// One release step in its own transaction: an expansion step while a marker is left, otherwise up to 256 ready
    /// operations, each applied with its final receipt.
    @discardableResult
    public func releaseStep() throws(CoreLedgerError) -> CoreReleaseStep {
        let time = now()
        return try write { session, records in
            if let (edges, enqueued) = try CoreCausalTables.expansionStep(in: session) {
                return .expanded(edges: edges, enqueued: enqueued)
            }
            let ready = try CoreCausalTables.readyBatch(in: session)
            guard !ready.isEmpty else { return .idle }
            let epoch = try Self.epoch(in: session)
            for operationID in ready {
                guard let operation = try CoreOperationRecords.operation(operationID, in: session) else {
                    throw CoreLedgerError.corrupt("a ready operation isn't stored")
                }
                _ = try self.apply(
                    try OperationEnvelope.decode(body: operation.body),
                    digest: OperationDigest.of(body: operation.body),
                    epoch: epoch, time: time, session: session, records: records)
            }
            return .released(ready)
        }
    }

    /// Runs release steps until nothing is left or `maxSteps` ran; returns the steps that did work.
    @discardableResult
    public func drainRelease(maxSteps: Int = .max) throws(CoreLedgerError) -> Int {
        var steps = 0
        while steps < maxSteps, try releaseStep() != .idle { steps += 1 }
        return steps
    }

    /// Operations waiting for dependencies, ready to release, and markers to expand.
    public func backlog() throws(CoreLedgerError) -> (waiting: Int, ready: Int, markers: Int) {
        try read { session, _ in try CoreCausalTables.counts(in: session) }
    }

    // MARK: - Receipts, pages and views

    /// The current receipt of an operation: provisional while it waits, final once decided (R2-L14's lookup).
    public func receipt(for operationID: Identifier128) throws(CoreLedgerError) -> SignedCoreReceipt? {
        try read { session, _ in
            try CoreOperationRecords.receipt(operationID, in: session).map { try SignedCoreReceipt(storedBytes: $0) }
        }
    }

    /// A signed change page for `partition` from `position` on (§8.4.2): every decision touching it in
    /// `(position, to]`, at most `maxEntries`, where `to` is the last entry's position when entries were left over and
    /// the newest position otherwise; `nil` when nothing was committed after `position`. A page that would pass
    /// 512 KiB carries fewer entries.
    public func changePage(partition: String, after position: Int64, maxEntries: Int = 256) throws(CoreLedgerError)
        -> SignedChangePage?
    {
        var limit = max(1, maxEntries)
        while true {
            let page: ChangePage? = try read { session, _ in
                guard
                    let row = try session.query(
                        "SELECT epoch_id, last_position FROM core_dataset WHERE singleton = 1"
                    ).first
                else { throw CoreLedgerError.corrupt("the dataset row") }
                let epoch = try CoreColumns.identifier(row[0])
                let head = try CoreColumns.integer(row[1])
                guard head > position else { return nil }
                let rows = try session.query(
                    """
                    SELECT c.position, c.decision, o.body, o.signature FROM core_change_log c
                    JOIN core_operations o ON o.operation_id = c.operation_id
                    WHERE c.position > ? AND c.partitions = ? ORDER BY c.position LIMIT ?
                    """, [.integer(position), .text(partition), .integer(Int64(limit + 1))])
                let taken = rows.prefix(limit)
                let to = rows.count > limit ? try CoreColumns.integer(taken[taken.endIndex - 1][0]) : head
                let entries = try taken.map { row in
                    guard let decision = ChangeEntry.Decision(rawValue: try CoreColumns.text(row[1])) else {
                        throw CoreLedgerError.corrupt("a change-log decision")
                    }
                    return try ChangeEntry(
                        position: try CoreColumns.integer(row[0]), partitions: [partition],
                        operation: try SignedOperation(
                            body: try CoreColumns.bytes(row[2]), signature: try CoreColumns.bytes(row[3])),
                        decision: decision)
                }
                return try ChangePage(
                    datasetID: datasetID, epochID: epoch, partitions: [partition], fromPosition: position,
                    toPosition: to, entries: entries)
            }
            guard let page else { return nil }
            do {
                return try ChangePageSigning.sign(page, with: signer)
            } catch {
                guard limit > 1, page.entries.count > 1 else { throw .signingFailed(String(describing: error)) }
                limit = page.entries.count / 2
            }
        }
    }

    /// The canonical merge view of a task at Core.
    public func taskView(_ entityID: Identifier128) throws(CoreLedgerError) -> TaskView? {
        try read { session, _ in try CoreTaskFold.view(entityID, in: session) }
    }

    public func securityEvents() throws(CoreLedgerError) -> [CoreSecurityEvent] {
        try read { session, _ in try CoreOperationRecords.securityEvents(in: session) }
    }

    // MARK: - Helpers

    /// M3-1 applies the item operations of the task family to tasks.
    static func isSupported(_ envelope: OperationEnvelope) -> Bool {
        envelope.entityType == "task" && ItemOperationPayload.operationTypes.contains(envelope.operationType)
    }

    /// The payload's schema and the rules the replica checks too (§8.2.3, §8.3.2).
    static func checkPayload(_ envelope: OperationEnvelope) throws(OperationEnvelopeError) {
        let decoded = try ItemOperationPayload(operationType: envelope.operationType, payload: envelope.payload)
        if case .conflictResolve(_, let value) = decoded {
            if let group = envelope.observed?.group {
                // Pages are numbered 1…count; only the last carries the value.
                guard (value != nil) == (group.index == group.count) else { throw .invalidField("observed.group") }
            } else if value == nil {
                throw .invalidField("payload.value")
            }
        }
    }

    static func epoch(in session: SQLiteSession) throws -> Identifier128 {
        guard let row = try session.query("SELECT epoch_id FROM core_dataset WHERE singleton = 1").first else {
            throw CoreLedgerError.corrupt("the dataset row")
        }
        return try CoreColumns.identifier(row[0])
    }

    static func nextPosition(in session: SQLiteSession) throws -> Int64 {
        try session.query("UPDATE core_dataset SET last_position = last_position + 1 WHERE singleton = 1")
        guard
            let position = try session.query(
                "SELECT last_position FROM core_dataset WHERE singleton = 1"
            ).first?.first?.integer
        else { throw CoreLedgerError.corrupt("the dataset row") }
        return position
    }

    static func logChange(
        _ position: Int64, _ operationID: Identifier128, decision: ChangeEntry.Decision, epoch: Identifier128,
        partition: String, in session: SQLiteSession
    ) throws {
        try session.query(
            "INSERT INTO core_change_log (position, operation_id, partitions, decision, epoch_id) VALUES (?, ?, ?, ?, ?)",
            [
                .integer(position), CoreColumns.id(operationID), .text(partition), .text(decision.rawValue),
                CoreColumns.id(epoch),
            ])
    }

    private func sign(_ receipt: CoreReceipt) throws -> SignedCoreReceipt {
        do {
            return try ReceiptSigning.sign(receipt, with: signer)
        } catch {
            throw CoreLedgerError.signingFailed(String(describing: error))
        }
    }

    func write<T>(_ body: (SQLiteSession, any RecordWriting) throws -> T) throws(CoreLedgerError) -> T {
        do {
            return try storage.records.ledgerWrite(body)
        } catch {
            throw CoreLedgerError.classify(error)
        }
    }

    func read<T>(_ body: (SQLiteSession, any RecordReading) throws -> T) throws(CoreLedgerError) -> T {
        do {
            return try storage.records.ledgerRead(body)
        } catch {
            throw CoreLedgerError.classify(error)
        }
    }
}
