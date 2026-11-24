// The client database (plan §8.6; R2-DATA-01, -02, R2-SYNC-02, -04): one replica per installation, opened by one
// process as its only writer and checkpointer (docs/DECISIONS.md D-55). Every launch that opens it starts a new
// incarnation (§8.1.1). A local change is one write transaction (§8.6.1): validation, the operation ID and this
// incarnation's next sequence, signing through `ReplicaSigning` or a draft when signing is unavailable (§8.6.2),
// storage, the index through `ReplicaIndexing`, the local change journal and its generation, and follow-up work.
// Nothing is reported saved unless that transaction committed.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// One installation's replica.
public final class ReplicaStore: Sendable {
    public let directory: ReplicaDirectory
    public let configuration: ReplicaStoreConfiguration
    /// This launch's incarnation.
    public let incarnationID: Identifier128
    private let database: SQLiteWALDatabase
    private let signing: any ReplicaSigning
    private let indexing: (any ReplicaIndexing)?
    private let now: @Sendable () -> Int64

    /// Opens (or creates) the replica in `directoryPath` as its only writer, and starts a new incarnation.
    /// - Parameter now: Unix milliseconds, for creation times; never used to order operations.
    public init(
        directoryPath: String, configuration: ReplicaStoreConfiguration = ReplicaStoreConfiguration(),
        signing: any ReplicaSigning, indexing: (any ReplicaIndexing)? = nil,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
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
        try directory.restoreBallast(bytes: configuration.captureReserveBytes)
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
    /// Every failure rolls everything back and is reported as it is (`storageFull`, `io`, `indexFailed`, …).
    public func save(_ command: LocalCommand) throws(ReplicaStoreError) -> LocalSaveResult {
        let operationID = Identifier128.random()
        try Self.validate(command, operationID: operationID, configuration: configuration)
        let time = now()
        return try write { session in
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
        try reindex(command.item, in: session)
        try FollowUpQueue.add(.submit, operationID, generation: generation, in: session)
        return .saved(
            operationID: operationID,
            origin: OriginTriple(device: deviceID, incarnation: incarnationID, sequence: sequence),
            generation: generation)
    }

    /// Checks the command as the widest operation it can become (sequence 1 with an incarnation link, the largest
    /// numbers), so a draft saved now can always be signed later within the 64 KiB body.
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
        } catch let error as OperationEnvelopeError {
            throw .invalidCommand(error)
        } catch {
            throw .corrupt("\(error)")
        }
    }

    // MARK: - Relayed operations and the duplicate rules (§8.2.1)

    /// Verifies an arriving operation (dataset, origin key, signature) and applies the duplicate rules: same ID and
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
                try self.reindex(item, in: session)
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
            if rejected { try self.reindex(entry.item, in: session) }
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
    private func reindex(_ item: ReplicaItemKey, in session: SQLiteSession) throws {
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
    private func write<T>(_ body: (SQLiteSession) throws -> T) throws(ReplicaStoreError) -> T {
        do {
            return try database.writer.writeTransaction(body)
        } catch {
            throw ReplicaStoreError.classify(error)
        }
    }

    private func read<T>(_ body: (SQLiteSession) throws -> T) throws(ReplicaStoreError) -> T {
        do {
            return try database.writer.readTransaction(body)
        } catch {
            throw ReplicaStoreError.classify(error)
        }
    }
}
