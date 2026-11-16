// The `email` section: the SMTP-over-TLS adapter Lisa sends from, with its password kept as a secret reference.

import LisaSecrets

/// The outbound SMTP adapter (EMAIL-01). Configuring it sends nothing: real email also needs `delivery.emailEnabled`,
/// an approved address and `delivery.modes.email` set to `live`, and goes only to approved addresses.
public struct EmailAdapterConfiguration: Hashable, Sendable {
    /// The SMTP server, such as `smtp.example.com`.
    public let host: String
    /// Defaults to 465 for implicit TLS and 587 for STARTTLS.
    public let port: Int
    /// TLS from the first byte, or a required STARTTLS upgrade; certificates are always validated.
    public let security: TransportSecurity
    /// The SMTP account name.
    public let username: String
    /// The reference to the SMTP password.
    public let passwordSecret: SecretReference
    /// Lisa's own address. It must not be one of the owner's approved addresses.
    public let fromAddress: String
    /// The display name on outgoing mail, such as "Lisa".
    public let fromName: String?

    static func decode(_ section: ConfigSection) -> EmailAdapterConfiguration? {
        defer { section.finish() }
        let host = section.requiredValidated(
            "host", maxLength: 253, fix: "name the SMTP server, such as smtp.example.com",
            NetworkAddressRules.serverHost)
        let security = section.choice("security", default: .implicitTLS, options: TransportSecurity.allCases)
        let port = section.integer("port", default: security == .implicitTLS ? 465 : 587, in: 1...65_535)
        let username = section.requiredText("username", maxLength: 320, fix: "the SMTP account name")
        let passwordSecret = section.requiredSecret(
            "passwordSecret", fix: "reference the SMTP password, such as env:LISA_SMTP_PASSWORD")
        let fromAddress = section.requiredValidated(
            "fromAddress", maxLength: 254, fix: "Lisa's own address, such as lisa@example.com",
            DeliveryConfiguration.emailAddress)
        let fromName = section.text("fromName", maxLength: 100)
        guard let host, let username, let passwordSecret, let fromAddress else { return nil }
        return EmailAdapterConfiguration(
            host: host, port: port, security: security, username: username, passwordSecret: passwordSecret,
            fromAddress: fromAddress, fromName: fromName)
    }
}
