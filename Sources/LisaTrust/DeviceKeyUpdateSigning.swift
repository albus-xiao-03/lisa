// A device's operation-key rotation (plan §8.1.4): the update record, signed by both the previous and the next key
// over the same body, in the same two-signature form as Core's key transitions.

import LisaCrypto
import LisaSyncProtocol

/// Signs and verifies device key updates.
public enum DeviceKeyUpdateSigning {
    /// The update, signed by the device's current key and by its next key.
    public static func sign(_ update: DeviceKeyUpdate, previous: some MessageSigning, next: some MessageSigning)
        throws -> SignedKeyTransition
    {
        guard previous.verifier.spkiDER == update.previousKey, next.verifier.spkiDER == update.nextKey else {
            throw KeyHistoryError.invalidKey
        }
        let body = try update.canonicalBody()
        return try SignedKeyTransition(
            body: body, previousSignature: try DomainSignatures.sign(body, domain: .deviceKeyUpdate, with: previous),
            nextSignature: try DomainSignatures.sign(body, domain: .deviceKeyUpdate, with: next))
    }

    /// The update and its next key, only if both keys it names signed these exact bytes.
    public static func verify(_ signed: SignedKeyTransition) throws(KeyHistoryError)
        -> (update: DeviceKeyUpdate, next: P256Verifier)
    {
        let update: DeviceKeyUpdate
        do {
            update = try DeviceKeyUpdate.decode(body: signed.body)
        } catch {
            throw .malformed(error)
        }
        guard let previous = try? P256Verifier(canonicalSPKI: update.previousKey),
            let next = try? P256Verifier(canonicalSPKI: update.nextKey)
        else { throw .invalidKey }
        guard
            DomainSignatures.isValid(
                signed.previousSignature, over: signed.body, domain: .deviceKeyUpdate, by: previous),
            DomainSignatures.isValid(signed.nextSignature, over: signed.body, domain: .deviceKeyUpdate, by: next)
        else { throw .invalidSignature }
        return (update, next)
    }
}
