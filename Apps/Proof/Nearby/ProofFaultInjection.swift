// PROOF ONLY — Apps/Proof never ships. The faults the owner can inject on one device for the N-1 refusal criteria
// (plan §10.5): each names the check it serves and the outcome the peer must show. Off by default; the chosen fault
// is recorded in every result it affects.

enum ProofFaultInjection: String, CaseIterable, Codable, Sendable {
    case none
    /// This side signs over an exporter value with one bit flipped, as a relay's second session would see it.
    case wrongExporterBinding = "wrong-exporter-binding"
    /// A throwaway device ID and keys that no roster lists: Design A's handshake has no pair key; under Design B
    /// this side presents its throwaway Secure Enclave identity, whose pin no roster lists, so the peer's verify
    /// block must refuse the handshake.
    case unenrolledIdentity = "unenrolled-identity"
    /// The enrolled transport identity with a throwaway operation key: TLS completes and the session layer must
    /// refuse the transcript signature.
    case unenrolledOperationKey = "unenrolled-operation-key"
    /// After authentication, a frame header declaring 1 MiB + 1 bytes: the peer must refuse it before allocating.
    case oversizeFrameHeader = "oversize-frame-header"

    /// The check of the cell record (`ProofCellCheck`) the fault serves.
    var check: ProofCellCheck? {
        switch self {
        case .none: nil
        case .wrongExporterBinding: .wrongBindingRefused
        case .unenrolledIdentity, .unenrolledOperationKey: .unenrolledRefused
        case .oversizeFrameHeader: .framesWithinBudget
        }
    }
}
