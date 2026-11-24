// A software operation key behind the signing port (plan §7.2.3: "software key in harnesses").

import LisaTrust

/// Signs with an in-memory key under the operation domain, or reports the key unavailable when it has none.
public struct SoftwareReplicaSigner: ReplicaSigning {
    let signer: (any MessageSigning)?

    /// - Parameter signer: the device's operation key; `nil` models a key that can't be used.
    public init(signer: (any MessageSigning)?) {
        self.signer = signer
    }

    public func signOperationBody(_ body: [UInt8]) -> ReplicaSignature {
        guard let signer, let signature = try? DomainSignatures.sign(body, domain: .operation, with: signer) else {
            return .keyUnavailable
        }
        return .signed(signature)
    }
}
