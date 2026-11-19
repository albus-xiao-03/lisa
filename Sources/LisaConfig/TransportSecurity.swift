// How a mail-server connection is protected: TLS from the first byte, or a required STARTTLS upgrade.

/// TLS for SMTP and IMAP connections. There is no plaintext option, and certificates are always validated.
public enum TransportSecurity: String, Hashable, Sendable, CaseIterable {
    /// TLS from the first byte (SMTP port 465, IMAP port 993).
    case implicitTLS
    /// A plaintext greeting upgraded with STARTTLS; the upgrade must succeed before anything else is sent
    /// (SMTP port 587, IMAP port 143).
    case startTLS
}
