// Every secret reference in a configuration, with its setting path, for checking access without reading values.

import LisaSecrets

/// A secret reference and the setting that holds it.
public struct ConfiguredSecret: Hashable, Sendable {
    /// The setting's path, such as `email.passwordSecret` or `sources[0].passwordSecret`.
    public let path: String
    /// Where the secret lives; it names a location, never a value.
    public let reference: SecretReference
}

extension LisaConfiguration {
    /// Every secret the configuration refers to. Verifying access resolves each through the secret store; the
    /// configuration itself never holds a secret value.
    public var referencedSecrets: [ConfiguredSecret] {
        var secrets: [ConfiguredSecret] = []
        func add(_ path: ConfigurationPath, _ reference: SecretReference?) {
            if let reference {
                secrets.append(ConfiguredSecret(path: path.description, reference: reference))
            }
        }
        add(ConfigurationPath("email", "passwordSecret"), email?.passwordSecret)
        add(ConfigurationPath("calls", "authTokenSecret"), calls?.authTokenSecret)
        add(ConfigurationPath("notifications", "apns", "signingKeySecret"), notifications.apns?.signingKeySecret)
        add(ConfigurationPath("model", "apiKeySecret"), model.apiKeySecret)
        add(ConfigurationPath("api", "tls", "certificateSecret"), api.tls.certificateSecret)
        add(ConfigurationPath("api", "tls", "privateKeySecret"), api.tls.privateKeySecret)
        for (index, source) in sources.enumerated() {
            let base = ConfigurationPath("sources").appending(index: index)
            switch source.settings {
            case .mailbox(let mailbox):
                add(base.appending(key: "passwordSecret"), mailbox.passwordSecret)
            case .calendarFeed(let feed):
                if case .secretURL(let reference) = feed.location {
                    add(base.appending(key: "urlSecret"), reference)
                }
            case .newsFeed(let feed):
                if case .secretURL(let reference) = feed.location {
                    add(base.appending(key: "urlSecret"), reference)
                }
            case .xAccount(let account):
                add(base.appending(key: "bearerTokenSecret"), account.bearerTokenSecret)
            case .discordChannel(let channel):
                add(base.appending(key: "botTokenSecret"), channel.botTokenSecret)
            case .localImport:
                break
            }
        }
        return secrets
    }
}
