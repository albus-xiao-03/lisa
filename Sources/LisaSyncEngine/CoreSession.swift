// A replica's session with Core on the direct path (plan §8.6.5), through the `CoreTransport` port: check the dataset,
// recover the baseline from signed pages, submit pending local work in the order it was saved, record each receipt
// only after verifying it by Core's key, then install the canonical state that work produced. Pending work is never
// discarded: anything Core refuses stays in the journal with its outcome. Trust, revocations, snapshots and nearby
// relay join this session in their spans.

import LisaCrypto
import LisaReplicaStore
import LisaSyncProtocol
import LisaTrust

/// The direct HTTPS path to Core, as the sync engine uses it (plan §7.2.3).
public protocol CoreTransport: Sendable {
    func capabilities() async throws -> SyncWire.Capabilities
    func submit(_ operations: [SignedOperation]) async throws -> [SyncWire.Outcome]
    func receipts(for operationIDs: [Identifier128]) async throws -> [(
        operationID: Identifier128, receipt: SignedCoreReceipt?
    )]
    func changes(partition: String, after position: Int64, limit: Int) async throws -> SignedChangePage?
}

/// Why a session stopped.
public enum CoreSessionError: Error, Hashable, Sendable {
    /// Core serves another dataset than the replica's.
    case datasetMismatch
    /// A page didn't move a partition forward; the session stops rather than loop.
    case noProgress(String)
}

/// What one reconciliation did.
public struct CoreSessionReport: Hashable, Sendable {
    public var pagesApplied = 0
    public var submitted = 0
    public var receiptsRecorded = 0
    /// Operations Core refused without a receipt (reuse, or not verified), by ID, with what Core said.
    public var refused: [Identifier128: String] = [:]

    public init() {}
}

/// One replica's session with Core.
public struct CoreSession: Sendable {
    let replica: ReplicaStore
    let transport: any CoreTransport
    let coreKey: P256Verifier
    let roster: @Sendable (Identifier128) -> P256Verifier?

    public init(
        replica: ReplicaStore, transport: any CoreTransport, coreKey: P256Verifier,
        roster: @escaping @Sendable (Identifier128) -> P256Verifier?
    ) {
        self.replica = replica
        self.transport = transport
        self.coreKey = coreKey
        self.roster = roster
    }

    /// Reconciles `partitions` with Core: baseline pages, pending submissions with their verified receipts, then the
    /// pages that carry the submitted work.
    public func reconcile(partitions: [String], pageLimit: Int = 256) async throws -> CoreSessionReport {
        var report = CoreSessionReport()
        let capabilities = try await transport.capabilities()
        guard capabilities.datasetID == (try replica.identity().datasetID) else {
            throw CoreSessionError.datasetMismatch
        }
        report.pagesApplied += try await pull(partitions, limit: pageLimit)
        _ = try replica.signHeldDrafts()
        let pending = try replica.journal().filter {
            $0.source == .local && ($0.state == .pending || $0.state == .submitted)
        }
        var start = 0
        while start < pending.count {
            let batch = Array(pending[start..<min(start + SyncWire.maximumItems, pending.count)])
            for entry in batch where entry.state == .pending { try replica.markSubmitted(entry.operationID) }
            let outcomes = try await transport.submit(batch.map(\.operation))
            report.submitted += batch.count
            for (entry, outcome) in zip(batch, outcomes) {
                switch outcome {
                case .receipted(let receipt), .duplicate(let receipt):
                    if try replica.recordReceipt(receipt, coreKey: coreKey) { report.receiptsRecorded += 1 }
                case .identityReuse: report.refused[entry.operationID] = "identity_reuse"
                case .sequenceReuse: report.refused[entry.operationID] = "sequence_reuse"
                case .unverified(let reason): report.refused[entry.operationID] = reason
                }
            }
            start += batch.count
        }
        report.pagesApplied += try await pull(partitions, limit: pageLimit)
        return report
    }

    /// Applies Core's pages for each partition from its cursor until Core has nothing newer.
    func pull(_ partitions: [String], limit: Int) async throws -> Int {
        var applied = 0
        for partition in partitions {
            while true {
                let cursor = try replica.partitionCursor(partition)?.position ?? 0
                guard let page = try await transport.changes(partition: partition, after: cursor, limit: limit) else {
                    break
                }
                let outcome = try replica.applyChangePage(page, coreKey: coreKey, deviceKey: roster)[partition]
                guard case .applied(let moved, _)? = outcome, moved > cursor else {
                    throw CoreSessionError.noProgress(partition)
                }
                applied += 1
            }
        }
        return applied
    }
}
