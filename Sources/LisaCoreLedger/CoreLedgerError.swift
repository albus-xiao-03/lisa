// Why a Core ledger call failed (plan §8.4.1). A failure rolls back the whole call; nothing failed is ever reported as
// decided.

import LisaSQLite
import LisaSyncProtocol

/// A Core ledger failure.
public enum CoreLedgerError: Error, Hashable, Sendable {
    /// The database refused or failed the work.
    case database(String)
    /// A stored row doesn't decode: the ledger is damaged.
    case corrupt(String)
    /// The ledger belongs to another dataset than the one asked for.
    case datasetMismatch
    /// Signing a receipt or a page failed.
    case signingFailed(String)
    /// Encoding a page, a chunk or a header failed.
    case encodingFailed(String)
    /// The signer is a key the history retired: Core never signs with a retired key (§8.1.4).
    case signerRetired
    /// The signer is not in the store's key history: import its transition first, or use the current key's private
    /// half (§8.1.4, `trust import-key`).
    case signerMismatch
    /// A key transition that doesn't continue the store's history, with the reason.
    case keyHistory(String)

    static func classify(_ error: any Error) -> CoreLedgerError {
        if let error = error as? CoreLedgerError { return error }
        if let error = error as? SQLiteError { return .database(error.message) }
        return .database(String(describing: error))
    }
}
