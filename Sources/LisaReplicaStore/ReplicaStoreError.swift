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
