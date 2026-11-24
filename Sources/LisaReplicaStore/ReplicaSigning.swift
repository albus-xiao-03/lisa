// The port that signs inside the local-change transaction (plan §7.2.3, §8.6.1 step 3, §8.6.2). Implemented by the
// Apple Keychain folder (a Secure Enclave or Keychain key) and, in harnesses, by `SoftwareReplicaSigner`.

/// What signing an operation body gave.
public enum ReplicaSignature: Hashable, Sendable {
    /// The raw 64-byte P-256 ECDSA signature over `"lisa-r2-op\n"` ‖ body by this device's operation key.
    case signed([UInt8])
    /// The key can't be used now (a Keychain error, or a this-device-only key missing after a restore to another
    /// device). The save still succeeds, as a draft.
    case keyUnavailable
}

/// Signs operation bodies with this device's operation key.
public protocol ReplicaSigning: Sendable {
    /// Signs `body`, the exact canonical bytes of an operation envelope, or reports the key unavailable. It never
    /// fails the save.
    func signOperationBody(_ body: [UInt8]) -> ReplicaSignature
}
