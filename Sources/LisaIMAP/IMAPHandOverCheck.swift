// Confirms, before Lisa sends anything, that libcurl handed over an authenticated session: the server lines libcurl
// read while connecting must show an OK greeting and a completed login (plan §7.2: "a runtime check confirms the
// session state before any command is sent").

/// Checks CurlIMAPSession's connect transcript, which holds the server's lines only (never libcurl's commands).
enum IMAPHandOverCheck {
    /// libcurl 8.14.1 sends CAPABILITY and then LOGIN or AUTHENTICATE, so a logged-in hand-over shows at least two
    /// tagged OK completions, the last of them as the final line (lib/imap.c, imap_connect).
    static let minimumCompletions = 2

    static func verify(_ transcript: [String]) throws(IMAPPassFailure) {
        guard let greeting = transcript.first?.uppercased() else {
            throw .failed(.parse, "libcurl handed over the connection without a server greeting")
        }
        if greeting.hasPrefix("* PREAUTH") {
            throw .failed(
                .capabilityDenied,
                "the IMAP server pre-authenticated the connection, so the configured account could not be confirmed; "
                    + "Lisa did not use it")
        }
        guard greeting.hasPrefix("* OK") else {
            throw .failed(.parse, "the IMAP server's greeting was not OK")
        }
        if transcript.contains(where: { $0.uppercased().hasPrefix("* BYE") }) {
            throw .failed(.network, "the IMAP server ended the session while Lisa was logging in")
        }
        guard let last = transcript.last, isTaggedOK(last),
            transcript.filter(isTaggedOK).count >= minimumCompletions
        else {
            throw .failed(.parse, "the connection was handed over without a completed login")
        }
    }

    /// A line `tag OK ...` whose tag is not `*` or `+`.
    static func isTaggedOK(_ line: String) -> Bool {
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count >= 2, fields[0] != "*", fields[0] != "+", !fields[0].isEmpty else { return false }
        return fields[1].uppercased() == "OK"
    }
}
