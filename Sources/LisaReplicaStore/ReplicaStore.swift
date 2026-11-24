// The client database (plan §8.6; R2-DATA-01, -02, R2-SYNC-02, -04): one replica per installation, opened by one
// process as its only writer and checkpointer (docs/DECISIONS.md D-55). Every launch that opens it starts a new
// incarnation (§8.1.1). A local change is one write transaction (§8.6.1): validation, the operation ID and this
// incarnation's next sequence, signing through `ReplicaSigning` or a draft when signing is unavailable (§8.6.2),
// storage, the index through `ReplicaIndexing`, the local change journal and its generation, and follow-up work.
// Nothing is reported saved unless that transaction committed.

import Foundation
import LisaCrypto
import LisaMerge
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// One installation's replica.
public final class ReplicaStore: Sendable {
    public let directory: ReplicaDirectory
    public let configuration: ReplicaStoreConfiguration
    /// This launch's incarnation.
    public let incarnationID: Identifier128
    /// The monitor of this replica's long reads: search, staging catch-up passes and export assembly (§8.15.2).
    public let readers: SQLiteReaderMonitor
    let database: SQLiteWALDatabase
    private let signing: any ReplicaSigning
    let indexing: (any ReplicaIndexing)?
    private let now: @Sendable () -> Int64
    private let freeSpace: @Sendable () -> Int64?

    /// Opens (or creates) the replica in `directoryPath` as its only writer, and starts a new incarnation.
    /// - Parameters:
    ///   - now: Unix milliseconds, for creation times; never used to order operations.
    ///   - freeSpace: the bytes available on the replica's file system, read fresh each time; `statvfs` by default.
    public init(
        directoryPath: String, configuration: ReplicaStoreConfiguration = ReplicaStoreConfiguration(),
        signing: any ReplicaSigning, indexing: (any ReplicaIndexing)? = nil,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) },
        freeSpace: (@Sendable () -> Int64?)? = nil
    ) throws(ReplicaStoreError) {
        let directory = try ReplicaDirectory.prepare(at: directoryPath)
        let incarnation = Identifier128.random()
        let database: SQLiteWALDatabase
        do {
            if !FileManager.default.fileExists(atPath: directory.databasePath) {
                // An empty file is a new database; SQLite gives its WAL and shared-memory files the same mode.
                guard
                    FileManager.default.createFile(
                        atPath: directory.databasePath, contents: nil, attributes: [.posixPermissions: 0o600])
                else { throw ReplicaStoreError.directory("cannot create \(directory.databasePath)") }
            }
            database = try SQLiteWALDatabase(path: directory.databasePath)
            let time = now()
            try database.writer.writeTransaction { session in
                try ReplicaSchema.migrate(session)
                if try session.query("SELECT 1 FROM replica_identity WHERE singleton = 1").isEmpty {
                    try session.query(
                        "INSERT INTO replica_identity (singleton, installation_id, created_at) VALUES (1, ?, ?)",
                        [ReplicaColumns.id(Identifier128.random()), .integer(time)])
                }
                try IncarnationChain.start(incarnation, at: time, in: session)
            }
        } catch {
            throw ReplicaStoreError.classify(error)
        }
        let databasePath = directory.databasePath
        let freeSpace = freeSpace ?? { SQLiteFreeSpace.availableBytes(at: databasePath) }
        if FileManager.default.fileExists(atPath: directory.ballastPath) {
            try Self.restoreBallastIfSpaceReturned(
                directory, reserveBytes: configuration.captureReserveBytes, available: freeSpace())
        } else {
            try directory.restoreBallast(bytes: configuration.captureReserveBytes)
        }
        readers = SQLiteReaderMonitor(
            database: database, reserveBytes: Int64(configuration.captureReserveBytes), freeSpace: freeSpace)
        if let interval = configuration.readerSampleInterval { readers.start(interval: interval) }
        self.freeSpace = freeSpace
        self.directory = directory
        self.configuration = configuration
        self.incarnationID = incarnation
        self.database = database
        self.signing = signing
        self.indexing = indexing
        self.now = now
    }

    // MARK: - Identity

    public func identity() throws(ReplicaStoreError) -> ReplicaIdentity {
        try read { session in try Self.identity(in: session) }
    }

    /// Records the dataset and this device's ID from enrollment. A replica never changes dataset; re-enrollment may
    /// give the device a new ID (§8.6.2).
    public func recordEnrollment(datasetID: Identifier128, deviceID: Identifier128) throws(ReplicaStoreError) {
        try write { session in
            let identity = try Self.identity(in: session)
            if let existing = identity.datasetID, existing != datasetID { throw ReplicaStoreError.datasetMismatch }
            try session.query(
                "UPDATE replica_identity SET dataset_id = ?, device_id = ? WHERE singleton = 1",
                [ReplicaColumns.id(datasetID), ReplicaColumns.id(deviceID)])
        }
    }

    public func incarnations() throws(ReplicaStoreError) -> [IncarnationRecord] {
        try read { session in try IncarnationChain.records(in: session) }
    }

    // MARK: - The atomic local change (§8.6.1)

    /// Saves one owner command in one write transaction: signed when enrolled with a usable key, otherwise as a draft.
    /// Every failure rolls everything back and is reported as it is (`storageFull`, `io`, `indexFailed`, …). This is
    /// the capture path: on `SQLITE_FULL` it empties the ballast and retries once (§8.15.2); if that succeeds the
    /// capture is saved and `storageIsAlmostFull` is true until the ballast is restored.
    public func save(_ command: LocalCommand) throws(ReplicaStoreError) -> LocalSaveResult {
        let operationID = Identifier128.random()
        try Self.validate(command, operationID: operationID, configuration: configuration)
        let time = now()
        do {
            return try saveOnce(command, operationID: operationID, time: time)
        } catch .storageFull where directory.ballastBytes > 0 {
            try directory.releaseBallast()
            return try saveOnce(command, operationID: operationID, time: time)
        }
    }

    /// Whether the ballast has been used and not yet restored: the app says "Storage is almost full".
    public var storageIsAlmostFull: Bool { directory.ballastBytes < configuration.captureReserveBytes }

    /// Writes other than captures read free space fresh at the start of each bounded transaction and stop before the
    /// capture reserve (§8.15.2): `estimate` more bytes must leave the reserve untouched.
    func requireRoomBeyondReserve(estimate: Int) throws(ReplicaStoreError) {
        guard let available = freeSpace() else { return }
        guard available - Int64(estimate) >= Int64(configuration.captureReserveBytes) else {
            throw .reserveProtected
        }
    }

    /// Restores the ballast once the space has returned: a full reserve must stay free after it. Returns whether the
    /// ballast is whole.
    @discardableResult
    public func restoreBallastIfSpaceReturned() throws(ReplicaStoreError) -> Bool {
        try Self.restoreBallastIfSpaceReturned(
            directory, reserveBytes: configuration.captureReserveBytes, available: freeSpace())
    }

    @discardableResult
    static func restoreBallastIfSpaceReturned(_ directory: ReplicaDirectory, reserveBytes: Int, available: Int64?)
        throws(ReplicaStoreError) -> Bool
    {
        let missing = reserveBytes - directory.ballastBytes
        guard missing > 0 else { return true }
        guard let available, available >= Int64(missing) + Int64(reserveBytes) else { return false }
        return try directory.restoreBallast(bytes: reserveBytes)
    }

    /// Runs a long read (search, a catch-up pass, export assembly) on its own read-only connection under the reader
    /// monitor. `readerReleased` means the monitor released it to protect storage or its budget: retry later.
    public func withLongReader<T>(_ purpose: SQLiteReaderPurpose, _ body: (SQLiteSession) throws -> T)
        throws(ReplicaStoreError) -> T
    {
        do {
            return try readers.withReader(purpose, body)
        } catch let error as SQLiteError where error.isInterrupted {
            throw .readerReleased(purpose.name)
        } catch {
            throw ReplicaStoreError.classify(error)
        }
    }

    private func saveOnce(_ command: LocalCommand, operationID: Identifier128, time: Int64) throws(ReplicaStoreError)
        -> LocalSaveResult
    {
        try write { session in
            // Aggregate limits are advisory (§8.3.2): checked only here, from this replica's own view, never while
            // merging, so merging stays deterministic.
            if command.operationType == "note.add", command.item.entityType == "task",
                let view = try Self.taskView(command.item.entityID, in: session),
                view.notes.count >= Self.advisoryNotesPerItem
            {
                throw ReplicaStoreError.aggregateLimit("notes")
            }
            let identity = try Self.identity(in: session)
            if let datasetID = identity.datasetID, let deviceID = identity.deviceID,
                let saved = try self.signAndStore(
                    command, operationID: operationID, createdAt: time, datasetID: datasetID, deviceID: deviceID,
                    fromDraft: false, in: session)
            {
                return saved
            }
            let reason: ReplicaDraft.Reason = identity.isEnrolled ? .keyUnavailable : .notEnrolled
            let generation = try LocalChangeJournal.append(
                .draftChange, operations: [operationID], items: [command.item], in: session)
            try DraftStore.insert(operationID, command: command, createdAt: time, reason: reason, in: session)
            try self.reindex(command.item, in: session)
            try FollowUpQueue.add(.signDraft, operationID, generation: generation, in: session)
            return .savedAsDraft(operationID: operationID, reason: reason, generation: generation)
        }
    }

    /// Signs held drafts in save order, each in its own transaction, under their own operation IDs and original times;
    /// stops at the first one the key can't sign. Returns the drafts signed.
    public func signHeldDrafts() throws(ReplicaStoreError) -> [LocalSaveResult] {
        var results: [LocalSaveResult] = []
        while let result = try write({ session -> LocalSaveResult? in
            let identity = try Self.identity(in: session)
            guard let datasetID = identity.datasetID, let deviceID = identity.deviceID,
                let draft = try DraftStore.firstHeld(in: session),
                let saved = try self.signAndStore(
                    draft.command, operationID: draft.operationID, createdAt: draft.createdAt, datasetID: datasetID,
                    deviceID: deviceID, fromDraft: true, in: session)
            else { return nil }
            try DraftStore.markSigned(draft.operationID, in: session)
            try FollowUpQueue.remove(.signDraft, draft.operationID, in: session)
            return saved
        }) {
            results.append(result)
        }
        return results
    }

    /// Builds, signs and stores one operation inside the caller's transaction. Returns `nil`, having written nothing,
    /// when the key is unavailable.
    private func signAndStore(
        _ command: LocalCommand, operationID: Identifier128, createdAt: Int64, datasetID: Identifier128,
        deviceID: Identifier128, fromDraft: Bool, in session: SQLiteSession
    ) throws -> LocalSaveResult? {
        let (sequence, previous) = try IncarnationChain.next(for: incarnationID, in: session)
        let envelope = try OperationEnvelope(
            schemaVersion: configuration.schemaVersion, datasetID: datasetID,
            origin: .device(deviceID: deviceID, incarnationID: incarnationID, sequence: sequence, previous: previous),
            operationID: operationID, entityType: command.item.entityType, entityID: command.item.entityID,
            operationType: command.operationType, payload: command.payload, dependencies: command.dependencies,
            observed: command.observed, policyVersion: configuration.policyVersion, legacyParent: nil,
            createdAt: createdAt)
        let body = try envelope.canonicalBody()
        guard case .signed(let signature) = signing.signOperationBody(body) else { return nil }
        let operation = try SignedOperation(body: body, signature: signature)
        try IncarnationChain.use(sequence, previous: previous, for: incarnationID, in: session)
        let generation = try LocalChangeJournal.append(
            .journalEntry, operations: [operationID], items: [command.item], in: session)
        try OperationJournal.insert(
            operation, envelope: envelope, digest: OperationDigest.of(body: body), source: .local,
            generation: generation, fromDraft: fromDraft, in: session)
        // A local operation enters the effective view at once; its marker later releases relayed dependents.
        try CausalReleaseTables.decide(operationID, .applied, in: session)
        try reindex(command.item, in: session)
        try FollowUpQueue.add(.submit, operationID, generation: generation, in: session)
        return .saved(
            operationID: operationID,
            origin: OriginTriple(device: deviceID, incarnation: incarnationID, sequence: sequence),
            generation: generation)
    }

    /// Checks the command as the widest operation it can become (sequence 1 with an incarnation link, the largest
    /// numbers), so a draft saved now can always be signed later within the 64 KiB body, and checks a payload whose
    /// schema is defined (`ItemOperationPayload`) by its rules and value budget.
    static func validate(_ command: LocalCommand, operationID: Identifier128, configuration: ReplicaStoreConfiguration)
        throws(ReplicaStoreError)
    {
        do {
            let widest = try Identifier128(bytes: [UInt8](repeating: 0xFF, count: 16))
            let envelope = try OperationEnvelope(
                schemaVersion: configuration.schemaVersion, datasetID: widest,
                origin: .device(
                    deviceID: widest, incarnationID: widest, sequence: 1,
                    previous: IncarnationLink(incarnationID: widest, lastSequence: .max)),
                operationID: operationID, entityType: command.item.entityType, entityID: command.item.entityID,
                operationType: command.operationType, payload: command.payload, dependencies: command.dependencies,
                observed: command.observed, policyVersion: configuration.policyVersion, legacyParent: nil,
                createdAt: .max)
            _ = try envelope.canonicalBody()
            try checkPayload(
                operationType: command.operationType, entityType: command.item.entityType, payload: command.payload,
                observed: command.observed)
        } catch let error as OperationEnvelopeError {
            throw .invalidCommand(error)
        } catch {
            throw .corrupt("\(error)")
        }
    }

    /// A payload whose schema is defined (`ItemOperationPayload`) is decoded and checked by its rules and value budget
    /// (plan §8.3.3), and a task operation must name a task.
    /// A resolution carries its value exactly when it is a single resolution or a group's last page.
    static func checkPayload(
        operationType: String, entityType: String, payload: CanonicalValue, observed: ObservedSet?
    ) throws(OperationEnvelopeError) {
        guard ItemOperationPayload.operationTypes.contains(operationType) else { return }
        let decoded = try ItemOperationPayload(operationType: operationType, payload: payload)
        if operationType.hasPrefix("task."), entityType != "task" { throw .invalidField("entity.type") }
        if case .conflictResolve(_, let value) = decoded {
            if let group = observed?.group {
                // Pages are numbered 1…count (ResolutionGroupPage); only the last carries the value.
                guard (value != nil) == (group.index == group.count) else { throw .invalidField("observed.group") }
            } else if value == nil {
                throw .invalidField("payload.value")
            }
        }
    }

    // MARK: - Relayed operations and the duplicate rules (§8.2.1)

    /// Verifies an arriving operation (dataset, origin key, signature, and a payload with a schema by its rules) and
    /// applies the duplicate rules: same ID and
    /// digest is a duplicate; same ID with another digest, or the same origin triple under another ID, is refused with
    /// a security event.
    public func receive(
        _ operation: SignedOperation, deviceKey: (Identifier128) -> P256Verifier?, coreKey: P256Verifier?
    ) throws(ReplicaStoreError) -> OperationIntakeResult {
        guard let datasetID = try identity().datasetID else { throw .notEnrolled }
        let envelope: OperationEnvelope
        do {
            envelope = try OperationSigning.verify(
                operation, dataset: datasetID, deviceKey: deviceKey, coreKey: coreKey)
        } catch {
            throw .unverified(error)
        }
        do {
            try Self.checkPayload(
                operationType: envelope.operationType, entityType: envelope.entityType, payload: envelope.payload,
                observed: envelope.observed)
        } catch {
            throw .unverified(.malformed(error))
        }
        let digest = OperationDigest.of(body: operation.body)
        let time = now()
        return try write { session in
            let byID = try OperationJournal.known(byID: envelope.operationID, in: session)
            let byOrigin = try envelope.origin.deviceTriple.flatMap { triple in
                try OperationJournal.known(
                    byOrigin: OriginTriple(
                        device: triple.device, incarnation: triple.incarnation, sequence: triple.sequence),
                    in: session)
            }
            switch OperationIdentityCheck.verdict(
                arrivingID: envelope.operationID, arrivingDigest: digest, byID: byID, byOrigin: byOrigin)
            {
            case .duplicate:
                guard let entry = try OperationJournal.entry(envelope.operationID, in: session) else {
                    throw ReplicaStoreError.corrupt("a duplicate's entry is missing")
                }
                return .duplicate(state: entry.state)
            case .identityReuse:
                guard let byID else { throw ReplicaStoreError.corrupt("identity reuse without an entry") }
                try OperationJournal.recordSecurityEvent(
                    .identityReuse, operationID: envelope.operationID, arrivingDigest: digest, known: byID, at: time,
                    in: session)
                return .rejectedIdentityReuse
            case .sequenceReuse:
                guard let byOrigin else { throw ReplicaStoreError.corrupt("sequence reuse without an entry") }
                try OperationJournal.recordSecurityEvent(
                    .sequenceReuse, operationID: envelope.operationID, arrivingDigest: digest, known: byOrigin,
                    at: time,
                    in: session)
                return .rejectedSequenceReuse
            case .new:
                let item = ReplicaItemKey(entityType: envelope.entityType, entityID: envelope.entityID)
                let generation = try LocalChangeJournal.append(
                    .journalEntry, operations: [envelope.operationID], items: [item], in: session)
                try OperationJournal.insert(
                    operation, envelope: envelope, digest: digest, source: .relayed, generation: generation,
                    fromDraft: false, in: session)
                // It enters the effective view when a release step finds every dependency decided (§8.2.2).
                _ = try CausalReleaseTables.intake(
                    envelope.operationID, origin: envelope.origin.deviceTriple?.device ?? Self.coreOrigin,
                    dependencies: envelope.dependencies, in: session)
                return .stored(generation: generation)
            }
        }
    }

    // MARK: - Receipts and canonical state

    /// Marks a pending entry as sent to Core.
    public func markSubmitted(_ operationID: Identifier128) throws(ReplicaStoreError) {
        try write { session in
            try session.query(
                "UPDATE operations SET state = 'submitted' WHERE operation_id = ? AND state = 'pending'",
                [ReplicaColumns.id(operationID)])
        }
    }

    /// Records a verified receipt. A final decision stands, and repeating a receipt changes nothing; a rejection takes
    /// the entry out of the effective view, while an acceptance leaves its overlay until canonical state containing it
    /// is installed (§8.6.4). Returns whether anything changed.
    @discardableResult
    public func recordReceipt(_ receipt: ReplicaReceipt) throws(ReplicaStoreError) -> Bool {
        try write { session in
            guard let entry = try OperationJournal.entry(receipt.operationID, in: session) else {
                throw ReplicaStoreError.unknownOperation(receipt.operationID)
            }
            guard entry.digest == receipt.digest else { throw ReplicaStoreError.receiptMismatch(receipt.operationID) }
            guard !entry.state.isFinal, entry.state != receipt.state || entry.receipt != receipt.signedBytes else {
                return false
            }
            let rejected = receipt.status == .rejected
            try LocalChangeJournal.append(
                rejected ? .rejection : .receipt, operations: [receipt.operationID], items: [entry.item], in: session)
            try OperationJournal.record(receipt, overlay: entry.isOverlay && !rejected, in: session)
            if rejected {
                try CausalReleaseTables.decide(receipt.operationID, .rejected, in: session)
                try self.reindex(entry.item, in: session)
            }
            try FollowUpQueue.remove(.submit, receipt.operationID, in: session)
            return true
        }
    }

    /// Installs a canonical row if its version is greater than the row's (§8.4.2); the overlays of the operations it
    /// contains leave the effective view in the same transaction. Returns whether it was installed.
    @discardableResult
    public func install(_ row: CanonicalRowInstall) throws(ReplicaStoreError) -> Bool {
        try write { session in
            let current = try session.query(
                "SELECT version FROM canonical_rows WHERE entity_type = ? AND entity_id = ?",
                [.text(row.item.entityType), ReplicaColumns.id(row.item.entityID)]
            ).first?.first?.integer
            if let current, row.version <= current { return false }
            try session.query(
                """
                INSERT INTO canonical_rows (entity_type, entity_id, version, body) VALUES (?, ?, ?, ?)
                ON CONFLICT (entity_type, entity_id) DO UPDATE SET version = excluded.version, body = excluded.body
                """,
                [
                    .text(row.item.entityType), ReplicaColumns.id(row.item.entityID), .integer(row.version),
                    ReplicaColumns.optionalBytes(row.body),
                ])
            for operation in row.operations {
                try session.query(
                    "UPDATE operations SET overlay = 0 WHERE operation_id = ? AND entity_type = ? AND entity_id = ?",
                    [ReplicaColumns.id(operation), .text(row.item.entityType), ReplicaColumns.id(row.item.entityID)])
            }
            try LocalChangeJournal.append(.canonicalPage, operations: row.operations, items: [row.item], in: session)
            try self.reindex(row.item, in: session)
            return true
        }
    }

    /// The installed canonical row of `item`: its version and body, `nil` body for a tombstone.
    public func canonicalRow(_ item: ReplicaItemKey) throws(ReplicaStoreError) -> (version: Int64, body: [UInt8]?)? {
        try read { session in
            guard
                let row = try session.query(
                    "SELECT version, body FROM canonical_rows WHERE entity_type = ? AND entity_id = ?",
                    [.text(item.entityType), ReplicaColumns.id(item.entityID)]
                ).first
            else { return nil }
            return (try ReplicaColumns.integer(row[0]), ReplicaColumns.optionalBytes(row[1]))
        }
    }

    // MARK: - Change pages and partition cursors (§8.4.2, §8.4.3)

    /// The cursor of `partition`, if the replica covers it.
    public func partitionCursor(_ partition: String) throws(ReplicaStoreError) -> PartitionCursor? {
        try read { session in try CanonicalTables.cursor(partition, in: session) }
    }

    /// Verifies one change page — Core's signature, its form, the dataset, and every entry's operation — and applies it
    /// in one transaction, per listed partition by the cases of §8.4.2. Each entry is applied once, subject to its row
    /// version; nothing missing from a page is read as deleted. A page that fails verification changes nothing.
    @discardableResult
    public func applyChangePage(
        _ signed: SignedChangePage, coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) -> [String: PartitionPageOutcome] {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        let page: ChangePage
        do {
            page = try ChangePageSigning.verify(signed, dataset: dataset, coreKey: coreKey)
        } catch {
            throw .unverifiedPage(error)
        }
        var envelopes: [OperationEnvelope] = []
        for entry in page.entries {
            do {
                envelopes.append(
                    try OperationSigning.verify(
                        entry.operation, dataset: dataset, deviceKey: deviceKey, coreKey: coreKey))
            } catch {
                throw .unverified(error)
            }
        }
        return try write { session in try self.apply(page, signed: signed, envelopes: envelopes, only: nil, in: session)
        }
    }

    /// Starts repairing `partition` (§8.4.3): pages that arrive for it meanwhile are kept, verified but unapplied.
    public func beginRepair(_ partition: String, epochID: Identifier128) throws(ReplicaStoreError) {
        try write { session in
            let current = try CanonicalTables.cursor(partition, in: session)
            try CanonicalTables.setCursor(
                partition, epoch: current?.epochID ?? epochID, position: current?.position ?? 0, repairing: true,
                in: session)
        }
    }

    /// Publishes a repair at its snapshot cut, then applies the pages deferred meanwhile, oldest interval first, for
    /// this partition only. The cursor becomes the cut if that is later; it never moves backward.
    @discardableResult
    public func finishRepair(
        _ partition: String, cut: Int64, coreKey: P256Verifier, deviceKey: (Identifier128) -> P256Verifier?
    ) throws(ReplicaStoreError) -> [PartitionPageOutcome] {
        guard let dataset = try identity().datasetID else { throw .notEnrolled }
        return try write { session in
            guard let current = try CanonicalTables.cursor(partition, in: session), current.isRepairing else {
                throw ReplicaStoreError.corrupt("\(partition) isn't being repaired")
            }
            try CanonicalTables.setCursor(
                partition, epoch: current.epochID, position: max(current.position, cut), repairing: false, in: session)
            var outcomes: [PartitionPageOutcome] = []
            for signed in try CanonicalTables.takeDeferred(partition, in: session) {
                let page = try ChangePageSigning.verify(signed, dataset: dataset, coreKey: coreKey)
                var envelopes: [OperationEnvelope] = []
                for entry in page.entries {
                    envelopes.append(
                        try OperationSigning.verify(
                            entry.operation, dataset: dataset, deviceKey: deviceKey, coreKey: coreKey))
                }
                if let outcome = try self.apply(
                    page, signed: signed, envelopes: envelopes, only: partition, in: session)[
                        partition]
                {
                    outcomes.append(outcome)
                }
            }
            return outcomes
        }
    }

    /// Applies a verified page inside the caller's transaction, for every listed partition or only `only`.
    private func apply(
        _ page: ChangePage, signed: SignedChangePage, envelopes: [OperationEnvelope], only: String?,
        in session: SQLiteSession
    ) throws -> [String: PartitionPageOutcome] {
        var outcomes: [String: PartitionPageOutcome] = [:]
        var from: [String: Int64] = [:]
        for partition in page.partitions where only == nil || only == partition {
            if let cursor = try CanonicalTables.cursor(partition, in: session) {
                if cursor.epochID != page.epochID {
                    outcomes[partition] = .otherEpoch
                } else if cursor.isRepairing {
                    try CanonicalTables.deferPage(signed, page: page, for: partition, in: session)
                    outcomes[partition] = .deferred
                } else if page.toPosition <= cursor.position {
                    outcomes[partition] = .ignored(cursor: cursor.position)
                } else if cursor.position < page.fromPosition {
                    outcomes[partition] = .gap(cursor: cursor.position)
                } else {
                    from[partition] = cursor.position
                }
            } else if page.fromPosition == 0 {
                from[partition] = 0
            } else {
                outcomes[partition] = .gap(cursor: nil)
            }
        }
        var counts: [String: Int] = [:]
        var operations: [Identifier128] = []
        var items: [ReplicaItemKey] = []
        for (entry, envelope) in zip(page.entries, envelopes) {
            let touched = entry.partitions.filter { partition in from[partition].map { entry.position > $0 } ?? false }
            guard !touched.isEmpty else { continue }
            for partition in touched { counts[partition, default: 0] += 1 }
            let item = ReplicaItemKey(entityType: envelope.entityType, entityID: envelope.entityID)
            if let version = try CanonicalTables.rowVersion(item, in: session), entry.position <= version { continue }
            try applyEntry(entry, envelope: envelope, epoch: page.epochID, item: item, in: session)
            operations.append(envelope.operationID)
            if !items.contains(item) { items.append(item) }
        }
        for partition in from.keys {
            try CanonicalTables.setCursor(
                partition, epoch: page.epochID, position: page.toPosition, repairing: false, in: session)
            outcomes[partition] = .applied(cursor: page.toPosition, entries: counts[partition] ?? 0)
        }
        if !from.isEmpty {
            try LocalChangeJournal.append(.canonicalPage, operations: operations, items: items, in: session)
        }
        for item in items { try reindex(item, in: session) }
        return outcomes
    }

    /// One entry: a committed operation joins canonical state (its journal copy, if any, records the commit and stops
    /// being an overlay), a rejected one leaves the view; either way its causal decision is made and the row's version
    /// moves to the entry's position.
    private func applyEntry(
        _ entry: ChangeEntry, envelope: OperationEnvelope, epoch: Identifier128, item: ReplicaItemKey,
        in session: SQLiteSession
    ) throws {
        let id = ReplicaColumns.id(envelope.operationID)
        switch entry.decision {
        case .accepted, .acceptedWithConflict:
            try CanonicalTables.insertCanonical(
                entry.operation, envelope: envelope, epoch: epoch, position: entry.position, decision: entry.decision,
                in: session)
            try session.query(
                """
                UPDATE operations SET state = ?, commit_epoch = ?, commit_position = ?, overlay = 0
                WHERE operation_id = ? AND state != 'rejected'
                """, [.text(entry.decision.rawValue), ReplicaColumns.id(epoch), .integer(entry.position), id])
            try CausalReleaseTables.decide(envelope.operationID, .applied, in: session)
        case .rejected:
            try session.query(
                """
                UPDATE operations SET state = 'rejected', commit_epoch = ?, commit_position = ?, overlay = 0
                WHERE operation_id = ?
                """, [ReplicaColumns.id(epoch), .integer(entry.position), id])
            try CausalReleaseTables.decide(envelope.operationID, .rejected, in: session)
        }
        try FollowUpQueue.remove(.submit, envelope.operationID, in: session)
        try CanonicalTables.setRowVersion(item, entry.position, in: session)
    }

    // MARK: - Causal release and the effective view (§8.2.2, §8.6.1)

    /// The advisory limit of notes per item (§8.3.2): past it the app asks the owner to archive.
    public static let advisoryNotesPerItem = 1_000

    /// The origin key of Core's legacy translation in round-robin release.
    // Sixteen bytes always make an identifier.
    static let coreOrigin = try! Identifier128(bytes: [UInt8](repeating: 0, count: 16))

    /// Runs one causal step in its own transaction: an expansion step while a marker is left, otherwise a release step,
    /// whose operations enter the effective view (one local change, the index updated).
    @discardableResult
    public func causalStep() throws(ReplicaStoreError) -> CausalStep {
        try requireRoomBeyondReserve(estimate: 1 << 20)
        return try write { session in
            if let (edges, enqueued) = try CausalReleaseTables.expansionStep(in: session) {
                return .expanded(edges: edges, enqueued: enqueued)
            }
            let released = try CausalReleaseTables.releaseStep(in: session)
            guard !released.isEmpty else { return .idle }
            var items: [ReplicaItemKey] = []
            for operation in released {
                guard let entry = try OperationJournal.entry(operation, in: session) else {
                    throw ReplicaStoreError.corrupt("a released operation isn't in the journal")
                }
                if !items.contains(entry.item) { items.append(entry.item) }
            }
            try LocalChangeJournal.append(.journalEntry, operations: released, items: items, in: session)
            for item in items { try self.reindex(item, in: session) }
            return .released(released)
        }
    }

    /// Runs causal steps until nothing is left or `maxSteps` ran; returns the steps that did work.
    @discardableResult
    public func drainCausalRelease(maxSteps: Int = .max) throws(ReplicaStoreError) -> Int {
        var steps = 0
        while steps < maxSteps, try causalStep() != .idle { steps += 1 }
        return steps
    }

    /// Operations waiting for dependencies, ready to release, and markers to expand.
    public func causalBacklog() throws(ReplicaStoreError) -> (waiting: Int, ready: Int, markers: Int) {
        try read { session in try CausalReleaseTables.counts(in: session) }
    }

    /// The effective view of one task (plan §8.6.1), or `nil` when the replica holds nothing of it.
    public func taskView(_ entityID: Identifier128) throws(ReplicaStoreError) -> TaskView? {
        try read { session in try Self.taskView(entityID, in: session) }
    }

    /// The effective view of one task inside the caller's transaction, for `ReplicaIndexing`: every journal entry of
    /// it that entered the view and wasn't rejected, with its commit position when known, and its held drafts, merged
    /// by `TaskMergeState`. Merging is a join, so the order of application doesn't change the result; causal order
    /// decides only what has entered the view.
    public static func taskView(_ entityID: Identifier128, in session: SQLiteSession) throws -> TaskView? {
        try taskView(entityID, in: session, canonicalTable: "canonical_operations")
    }

    /// The task's view over the live canonical table or a staged one (§8.6.3).
    static func taskView(_ entityID: Identifier128, in session: SQLiteSession, canonicalTable: String) throws
        -> TaskView?
    {
        let item = ReplicaItemKey(entityType: "task", entityID: entityID)
        let partition = CollectionPartition.name(forEntityType: "task") ?? "tasks"
        // Canonical operations first, then the journal's applied, unrejected ones not already canonical: each once.
        let canonical = try session.query(
            "SELECT body, epoch_id, position FROM \(canonicalTable) WHERE entity_type = ? AND entity_id = ?",
            [.text(item.entityType), ReplicaColumns.id(entityID)])
        let journal = try session.query(
            """
            SELECT o.body, o.commit_epoch, o.commit_position FROM operations o
            JOIN causal_decisions d ON d.operation_id = o.operation_id AND d.decision = 'applied'
            WHERE o.entity_type = ? AND o.entity_id = ? AND o.state != 'rejected'
              AND NOT EXISTS (SELECT 1 FROM \(canonicalTable) c WHERE c.operation_id = o.operation_id)
            """, [.text(item.entityType), ReplicaColumns.id(entityID)])
        let rows = canonical + journal
        let drafts = try DraftStore.held(for: item, in: session)
        guard !rows.isEmpty || !drafts.isEmpty else { return nil }
        var state = TaskMergeState()
        var groups:
            [Identifier128: [(envelope: OperationEnvelope, payload: ItemOperationPayload, commit: CommitPosition?)]] =
                [:]
        for row in rows {
            let envelope = try OperationEnvelope.decode(body: ReplicaColumns.bytes(row[0]))
            guard ItemOperationPayload.operationTypes.contains(envelope.operationType) else { continue }
            let payload = try ItemOperationPayload(operationType: envelope.operationType, payload: envelope.payload)
            var commit: CommitPosition?
            if let epoch = try ReplicaColumns.optionalIdentifier(row[1]),
                let position = ReplicaColumns.optionalInteger(row[2])
            {
                commit = CommitPosition(epochID: epoch, partition: partition, position: position)
            }
            if case .conflictResolve = payload, let group = envelope.observed?.group {
                groups[group.groupID, default: []].append((envelope, payload, commit))
                continue
            }
            state.apply(
                payload, id: envelope.operationID, observed: envelope.observed.map(ObservedCoverage.init) ?? .nothing,
                commit: commit)
        }
        // A paged resolution group applies atomically, as its last page observing every page's candidates, once all
        // its pages are present and their sorted IDs match the list digest; until then it changes nothing (§8.3.2).
        for pages in groups.values {
            guard let resolution = Self.completeGroup(pages.map { ($0.envelope, $0.payload) }),
                let last = pages.first(where: { $0.envelope.operationID == resolution.operationID })
            else { continue }
            state.apply(last.payload, id: resolution.operationID, observed: resolution.observed, commit: last.commit)
        }
        for draft in drafts {
            guard ItemOperationPayload.operationTypes.contains(draft.command.operationType) else { continue }
            let payload = try ItemOperationPayload(
                operationType: draft.command.operationType, payload: draft.command.payload)
            state.apply(
                payload, id: draft.operationID, observed: draft.command.observed.map(ObservedCoverage.init) ?? .nothing)
        }
        return state.view
    }

    /// A complete, consistent resolution group: every index of one count and list digest present once, one field, and
    /// the SHA-256 of the sorted, concatenated 16-byte IDs of all pages equal to the list digest. Returns the last page's
    /// operation ID and the coverage it applies with: its horizon and every page's explicit candidates.
    static func completeGroup(_ pages: [(envelope: OperationEnvelope, payload: ItemOperationPayload)])
        -> (operationID: Identifier128, observed: ObservedCoverage)?
    {
        guard let first = pages.first?.envelope.observed?.group, pages.count == Int(first.count) else { return nil }
        var byIndex: [Int64: (envelope: OperationEnvelope, payload: ItemOperationPayload)] = [:]
        var field: TaskField?
        for page in pages {
            guard let group = page.envelope.observed?.group, group.count == first.count,
                group.listDigest == first.listDigest, byIndex[group.index] == nil,
                case .conflictResolve(let pageField, _) = page.payload, field == nil || field == pageField
            else { return nil }
            field = pageField
            byIndex[group.index] = page
        }
        guard let last = byIndex[first.count], (1...first.count).allSatisfy({ byIndex[$0] != nil }) else {
            return nil
        }
        let ids = Set(pages.flatMap { $0.envelope.observed?.pieces ?? [] }).sorted {
            $0.bytes.lexicographicallyPrecedes($1.bytes)
        }
        let digest = [UInt8](Digests.sha256(Data(ids.flatMap(\.bytes))))
        guard digest == first.listDigest.bytes else { return nil }
        return (last.envelope.operationID, ObservedCoverage(horizon: last.envelope.observed?.horizon, pieces: Set(ids)))
    }

    /// The texts of `item`'s effective view that a search finds it by, inside the caller's transaction: a task's
    /// surviving titles, notes and tags; nothing for a deleted item or one the replica doesn't hold.
    public static func searchableText(of item: ReplicaItemKey, in session: SQLiteSession) throws -> [String] {
        try searchableText(of: item, in: session, canonicalTable: "canonical_operations")
    }

    static func searchableText(of item: ReplicaItemKey, in session: SQLiteSession, canonicalTable: String) throws
        -> [String]
    {
        switch item.entityType {
        case "task":
            guard let view = try taskView(item.entityID, in: session, canonicalTable: canonicalTable), !view.isDeleted
            else { return [] }
            return view.title + view.notes + view.tags
        default:
            return []
        }
    }

    // MARK: - Reading

    public func journalEntry(_ operationID: Identifier128) throws(ReplicaStoreError) -> JournalEntry? {
        try read { session in try OperationJournal.entry(operationID, in: session) }
    }

    /// Every journal entry in the order this replica stored them.
    public func journal() throws(ReplicaStoreError) -> [JournalEntry] {
        try read { session in try OperationJournal.entries(in: session) }
    }

    /// The entries of `item` still in the effective view, in the order this replica stored them.
    public func overlays(for item: ReplicaItemKey) throws(ReplicaStoreError) -> [JournalEntry] {
        try read { session in try OperationJournal.overlays(for: item, in: session) }
    }

    public func drafts() throws(ReplicaStoreError) -> [ReplicaDraft] {
        try read { session in try DraftStore.all(in: session) }
    }

    public func followUps() throws(ReplicaStoreError) -> [ReplicaFollowUp] {
        try read { session in try FollowUpQueue.all(in: session) }
    }

    public func securityEvents() throws(ReplicaStoreError) -> [ReplicaSecurityEvent] {
        try read { session in try OperationJournal.securityEvents(in: session) }
    }

    /// The local state generation.
    public func generation() throws(ReplicaStoreError) -> Int64 {
        try read { session in try LocalChangeJournal.generation(in: session) }
    }

    /// The local changes after `generation`, oldest first, at most `limit` (§8.6.3 catch-up passes read 512).
    public func changes(after generation: Int64, limit: Int) throws(ReplicaStoreError) -> [LocalChange] {
        try read { session in try LocalChangeJournal.changes(after: generation, limit: limit, in: session) }
    }

    // MARK: - Internals

    private static func identity(in session: SQLiteSession) throws -> ReplicaIdentity {
        guard
            let row = try session.query(
                "SELECT installation_id, dataset_id, device_id, created_at FROM replica_identity WHERE singleton = 1"
            ).first
        else { throw ReplicaStoreError.corrupt("the replica identity row is missing") }
        return ReplicaIdentity(
            installationID: try ReplicaColumns.identifier(row[0]),
            datasetID: try ReplicaColumns.optionalIdentifier(row[1]),
            deviceID: try ReplicaColumns.optionalIdentifier(row[2]), createdAt: try ReplicaColumns.integer(row[3]))
    }

    /// Calls the index port; its failure rolls the change back, a storage failure keeping its own classification.
    func reindex(_ item: ReplicaItemKey, in session: SQLiteSession) throws {
        guard let indexing else { return }
        do {
            try indexing.itemChanged(item, in: session)
        } catch let error as SQLiteError {
            throw error
        } catch {
            throw ReplicaStoreError.indexFailed("\(error)")
        }
    }

    @discardableResult
    func write<T>(_ body: (SQLiteSession) throws -> T) throws(ReplicaStoreError) -> T {
        do {
            return try database.writer.writeTransaction(body)
        } catch {
            throw ReplicaStoreError.classify(error)
        }
    }

    func read<T>(_ body: (SQLiteSession) throws -> T) throws(ReplicaStoreError) -> T {
        do {
            return try database.writer.readTransaction(body)
        } catch {
            throw ReplicaStoreError.classify(error)
        }
    }
}
