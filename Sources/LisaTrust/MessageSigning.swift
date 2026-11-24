// The signing boundary: software keys here, Secure Enclave or Keychain keys in Apps/Shared/Keychain (plan §7.2.3).

import LisaCrypto

/// Something that produces raw 64-byte P-256 signatures over exact message bytes. Core and harnesses use the
/// software `P256RawSigner`; the Apple apps provide a Secure Enclave or Keychain implementation.
public protocol MessageSigning: Sendable {
    /// The raw `r ‖ s` signature over `message`.
    func rawSignature(for message: [UInt8]) throws -> [UInt8]
    /// The verification key for these signatures.
    var verifier: P256Verifier { get }
}

extension P256RawSigner: MessageSigning {
    public func rawSignature(for message: [UInt8]) throws -> [UInt8] {
        try signature(for: message)
    }
}
