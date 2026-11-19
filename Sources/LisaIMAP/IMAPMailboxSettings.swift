// The configuration of Lisa's IMAP mailbox connector (MAIL-01): server, TLS mode, account, folder, address policy,
// message-size limit and timeouts. The password is a secret reference, resolved only when a pass starts.

import LisaCurl
import LisaHTTP
import LisaSecrets

/// How to reach and read Lisa's dedicated mailbox. Never the owner's personal mailbox.
public struct IMAPMailboxSettings: Hashable, Sendable {
    /// The IMAP server: a DNS name, or an IPv4 or IPv6 address literal (IPv6 without brackets).
    public var host: String
    public var port: Int
    /// Implicit TLS (usually port 993) or a required STARTTLS upgrade (usually port 143). There is no plaintext
    /// mode, and the server's certificate and name are always verified.
    public var security: CurlMailSecurity
    /// The account name of Lisa's mailbox.
    public var username: String
    /// The mailbox password, resolved from the secret store at the start of every pass.
    public var password: SecretReference
    /// The folder read, `INBOX` by default: 1 to 255 printable ASCII characters.
    public var folder: String
    /// The addresses the server may resolve to. LisaHost passes `.allowLocalNetworks` only when the configured host
    /// is a loopback or private address literal; `.loopbackOnly` is for local model servers and is refused here.
    public var addresses: AddressPolicy
    /// Messages larger than this (by the server's RFC822.SIZE) are not downloaded. Each one is reported in the
    /// batch's capability notes and stays in the mailbox; the cursor moves past it.
    public var maxMessageBytes: Int
    /// Name resolution and TCP and TLS setup, at most.
    public var connectTimeoutSeconds: Double
    /// The longest wait for the complete response to EXAMINE, UID SEARCH or a size probe, and for further bytes
    /// while messages are being received. Capped by the pass limit, it also bounds libcurl's own commands.
    public var commandTimeoutSeconds: Int
    /// A PEM bundle that replaces the system trust store; verification stays on. Only for loopback verification
    /// against a synthetic certificate authority: Lisa's host never sets it.
    public var trustStorePath: String?

    public init(
        host: String, port: Int, security: CurlMailSecurity, username: String, password: SecretReference,
        folder: String = "INBOX", addresses: AddressPolicy = .publicOnly, maxMessageBytes: Int = 25_000_000,
        connectTimeoutSeconds: Double = 15, commandTimeoutSeconds: Int = 30, trustStorePath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.username = username
        self.password = password
        self.folder = folder
        self.addresses = addresses
        self.maxMessageBytes = maxMessageBytes
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.trustStorePath = trustStorePath
    }
}
