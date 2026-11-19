// Resolves the model endpoint's API key from the secret store for each request and checks that it is safe to send.

import LisaInference
import LisaRedaction
import LisaSecrets

/// The optional API key. It is read for each request, so a missing or changed secret is noticed without a restart;
/// failures name only the secret's reference, never its value, and leave the affected items waiting for a model.
enum ModelAPIKey {
    /// The longest key accepted.
    static let maxLength = 4_096

    static func resolve(_ reference: SecretReference, from secrets: any SecretStore) throws(ModelError)
        -> Sensitive<String>
    {
        let key: Sensitive<String>
        do {
            key = try secrets.secret(for: reference)
        } catch let error as SecretStoreError {
            throw ModelError.unavailable("the model API key could not be read: \(error.description)")
        } catch {
            throw ModelError.unavailable("the model API key \(reference) could not be read")
        }
        guard (1...maxLength).contains(key.revealed.utf8.count),
            key.revealed.utf8.allSatisfy({ (0x21...0x7E).contains($0) })
        else {
            throw ModelError.unavailable(
                "the model API key \(reference) contains spaces or characters that cannot be sent in a header")
        }
        return key
    }
}
