// Why a replica store operation failed (plan §8.6.1, §8.6.2, §8.15.2). A failure is reported as it is: nothing that
// failed is ever reported as saved.

import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// A replica store failure.
public enum ReplicaStoreError: Error, Hashable, Sendable {
    /// The replica directory couldn't be created or made owner-only.
    case directory(String)
    /// `SQLITE_FULL` or `ENOSPC`: "Not saved: storage is full". The transaction was rolled back; earlier saves are
    /// intact.
    case storageFull
    /// An I/O failure (`SQLITE_IOERR`), reported as it is.
    case io(String)
    /// Another SQLite failure.
    case database(SQLiteError)
    /// The database was written by a newer schema than this build knows.
    case newerSchema(Int)
    /// The database's contents break the store's own invariants.
    case corrupt(String)
    /// The command isn't a valid operation (`rejected: malformed` if it were sent).
    case invalidCommand(OperationEnvelopeError)
    /// An arriving operation failed verification before its payload was looked at.
    case unverified(OperationVerificationError)
    /// A change page failed verification (Core's signature, its form, the dataset) before any entry was applied.
    case unverifiedPage(ChangePageVerificationError)
    /// The store needs an enrolled dataset and device for this.
    case notEnrolled
    /// No journal entry has this operation ID.
    case unknownOperation(Identifier128)
    /// A receipt names another digest than the journal holds for its operation.
    case receiptMismatch(Identifier128)
    /// Enrollment named another dataset than the replica already belongs to.
    case datasetMismatch
    /// The index couldn't follow the change (`ReplicaIndexing`), so the change was rolled back.
    case indexFailed(String)
    /// The reader monitor released this long read (its budget, or storage); retry it later (§8.15.2).
    case readerReleased(String)
    /// The item reached an advisory aggregate limit (1,000 notes): the app asks the owner to archive (§8.3.2).
    case aggregateLimit(String)
    /// A snapshot chunk isn't included under the signed snapshot header's root at its index (§8.4.3).
    case snapshotChunkNotIncluded(Int64)
    /// No snapshot installation is being staged.
    case noInstallation
    /// A partition snapshot's cut is older than the partition's cursor; it is refused (§8.4.3 step 1).
    case staleSnapshot
    /// A partition repair can't publish yet: chunks of its snapshot are missing.
    case repairIncomplete(Int)
    /// A partition repair's re-check failed (another epoch, or its cursor moved): the repair is abandoned.
    case repairAbandoned(String)
    /// A write other than a capture stopped before the capture reserve (§8.15.2): staging, a release step or an
    /// installation; it is retried when space returns, and captures keep their room.
    case reserveProtected
    /// A custody acknowledgement that didn't verify (§8.6.1).
    case unverifiedCustody(CustodyVerificationError)
    /// A Core receipt that didn't verify by Core's key (§8.2.1).
    case unverifiedReceipt(ReceiptVerificationError)
    /// A verified custody acknowledgement the replica can't take: for other bytes than the journal's, from this
    /// device, or from a revoked device.
    case custodyRefused(String)
    /// A roster that didn't verify by the trusted Core key, or wasn't newer than the one held (§8.1.3).
    case unverifiedRoster(RosterVerificationError)
    /// An enrollment completion for another device's trust than the one this replica already holds.
    case trustMismatch

    /// Classifies a failure raised while using the database.
    static func classify(_ error: any Error) -> ReplicaStoreError {
        if let error = error as? ReplicaStoreError { return error }
        if let error = error as? OperationEnvelopeError { return .invalidCommand(error) }
        guard let error = error as? SQLiteError else { return .corrupt("\(error)") }
        switch error.code {
        case 13: return .storageFull
        case 10: return .io(error.message)
        default: return .database(error)
        }
    }
}
