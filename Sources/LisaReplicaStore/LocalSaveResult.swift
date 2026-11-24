// What a committed local save produced (plan §8.6.1, §8.6.2). The app says "saved" only from one of these, which
// exist only after the write transaction committed.

import LisaSyncProtocol

/// A committed local save.
public enum LocalSaveResult: Hashable, Sendable {
    /// Signed and stored: "Saved on this device".
    case saved(operationID: Identifier128, origin: OriginTriple, generation: Int64)
    /// Stored as a draft under the operation ID it will be signed with: "Saved on this device — not connected to your
    /// Lisa yet", or "— can't be sent until this device is enrolled again".
    case savedAsDraft(operationID: Identifier128, reason: ReplicaDraft.Reason, generation: Int64)

    public var operationID: Identifier128 {
        switch self {
        case .saved(let id, _, _), .savedAsDraft(let id, _, _): id
        }
    }

    public var generation: Int64 {
        switch self {
        case .saved(_, _, let generation), .savedAsDraft(_, _, let generation): generation
        }
    }
}
