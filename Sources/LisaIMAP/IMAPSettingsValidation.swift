// Checks of the mailbox settings, the resolved password and the pass limits, before anything is sent. Every message
// names the setting, never a secret value.

import LisaHTTP
import LisaPorts

extension IMAPMailboxSettings {
    /// The largest per-message limit accepted.
    static let maxMessageBytesCeiling = 1_000_000_000
    /// The longest timeout accepted, in seconds.
    static let maxTimeoutSeconds = 600

    /// The first problem with these settings, or nil when they can be used.
    var configurationProblem: String? {
        if !IMAPHostName.isWellFormed(host) {
            return "the IMAP host must be a DNS name or an IP address literal"
        }
        if !(1...65_535).contains(port) { return "the IMAP port must be between 1 and 65535" }
        if username.isEmpty || username.utf8.count > 320 || username.utf8.contains(where: Self.isForbiddenInCommand) {
            return "the IMAP user name must be 1 to 320 bytes without line breaks or NUL"
        }
        if IMAPMailboxName(folder) == nil {
            return "the IMAP folder must be 1 to 255 printable ASCII characters"
        }
        switch addresses {
        case .publicOnly, .allowLocalNetworks:
            break
        case .loopbackOnly:
            return "the loopback-only address policy is for local model servers; mail uses publicOnly or "
                + "allowLocalNetworks"
        }
        if let literal = IPLiteral.parse(host), !addresses.permits(literal) {
            return "the IMAP host is a \(literal.addressClass.rawValue) address, which this address policy does not "
                + "allow"
        }
        if !(1...Self.maxMessageBytesCeiling).contains(maxMessageBytes) {
            return "the message size limit must be between 1 and \(Self.maxMessageBytesCeiling) bytes"
        }
        if !connectTimeoutSeconds.isFinite || connectTimeoutSeconds <= 0
            || connectTimeoutSeconds > Double(Self.maxTimeoutSeconds)
        {
            return "the connect timeout must be more than 0 and at most \(Self.maxTimeoutSeconds) seconds"
        }
        if !(1...Self.maxTimeoutSeconds).contains(commandTimeoutSeconds) {
            return "the command timeout must be between 1 and \(Self.maxTimeoutSeconds) seconds"
        }
        if let path = trustStorePath, !path.hasPrefix("/") || path.utf8.contains(0) {
            return "the trust store must be an absolute path"
        }
        return nil
    }

    /// The problem with a resolved password, described without revealing it. libcurl sends it inside an IMAP
    /// command or SASL exchange, where a line break or NUL could not be sent safely.
    static func passwordProblem(_ password: String) -> String? {
        if password.isEmpty { return "the mailbox password is empty" }
        if password.utf8.count > 1_024 { return "the mailbox password is longer than 1024 bytes" }
        if password.utf8.contains(where: isForbiddenInCommand) {
            return "the mailbox password contains a line break or NUL, which cannot be sent"
        }
        return nil
    }

    /// The problem with pass limits, or nil.
    static func limitsProblem(_ limits: SyncLimits) -> String? {
        if limits.maxItems < 1 { return "the items per pass must be at least 1" }
        if limits.maxBytes < 1 { return "the bytes per pass must be at least 1" }
        if limits.timeoutSeconds < 1 { return "the pass timeout must be at least 1 second" }
        return nil
    }

    private static func isForbiddenInCommand(_ byte: UInt8) -> Bool { byte == 0x00 || byte == 0x0A || byte == 0x0D }
}

/// Host names Lisa connects to: DNS names of letters, digits, hyphens and underscores in dot-separated labels, or
/// IP address literals.
enum IMAPHostName {
    static func isWellFormed(_ host: String) -> Bool {
        if IPLiteral.parse(host) != nil { return true }
        var name = Substring(host)
        if name.hasSuffix(".") { name = name.dropLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        // RFC 3696 §2 advises checking that the apparent top-level label is not all-numeric. Names such as 1.2.3 or
        // 017.0.0.1 are address spellings a resolver may read as IPv4 in other notations; only strict literals pass.
        if let last = labels.last, last.utf8.allSatisfy({ (0x30...0x39).contains($0) }) { return false }
        return labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                        || byte == 0x2D || byte == 0x5F
                }
        }
    }
}
