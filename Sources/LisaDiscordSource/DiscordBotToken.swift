// Resolves the Discord bot token from the secret store at fetch time and checks that it is safe to send.

import LisaPorts
import LisaRedaction
import LisaSecrets

/// The bot token. It is read for each fetch, so a missing or changed secret is noticed without a restart, and failures
/// name only the secret's reference, never its value.
enum DiscordBotToken {
    /// The longest token accepted.
    static let maxLength = 4_096

    static func resolve(_ reference: SecretReference, from secrets: any SecretStore) throws(ConnectorError)
        -> Sensitive<String>
    {
        let token: Sensitive<String>
        do {
            token = try secrets.secret(for: reference)
        } catch let error as SecretStoreError {
            throw ConnectorError(.configuration, "the Discord bot token could not be read: \(error.description)")
        } catch {
            throw ConnectorError(.configuration, "the Discord bot token \(reference) could not be read")
        }
        guard isHeaderSafe(token.revealed) else {
            throw ConnectorError(
                .configuration,
                "the Discord bot token \(reference) contains spaces or characters that cannot be sent in a header;"
                    + " store the token alone, without a \"Bot \" prefix")
        }
        return token
    }

    /// Visible ASCII only (0x21 to 0x7E), at most `maxLength` bytes: nothing that could break or extend a header.
    static func isHeaderSafe(_ token: String) -> Bool {
        (1...maxLength).contains(token.utf8.count) && token.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }
}
