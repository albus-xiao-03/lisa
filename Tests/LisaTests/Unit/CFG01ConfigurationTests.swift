// Unit tests for CFG-01, configuration (CFG-01, CFG-02; docs/SETUP-LINUX.md §6, config.example.json5): the repository's
// commented example reads and validates, covers every top-level section of the schema, and as written contacts no one.
// A syntax error is reported at the line and column where it is, counted in characters and the same with CRLF line
// endings, whether the text comes from a file or not. Unknown keys and unsafe settings are refused with actionable
// messages: every issue at once, in document order, each naming the setting, its line and column, the problem and the
// fix, and never repeating a secret written inline. A configuration that does not set delivery modes leaves every
// external delivery a dry run, even with every adapter configured and enabled; real delivery is a separate step for
// each channel.

import Foundation
import LisaConfig
import LisaDomain
import LisaHost
import Testing

@Suite("CFG-01 — Configuration", .tags(.unit))
struct CFG01ConfigurationTests {
    /// The home directory that a leading `~` expands to in these tests.
    private static let home = "/home/synthetic-owner"

    /// Marks, in a test's configuration text, where an issue must be reported. It is removed before the text is read.
    private static let marker: Character = "‸"

    /// The repository's example configuration, found from this file's place in the repository.
    private static let examplePath: String = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("config.example.json5").path
    }()

    /// A 1-based line and column, counted in characters.
    private struct Position: Equatable {
        var line: Int
        var column: Int
    }

    /// Configuration text without its markers, and where each marker was.
    private struct Marked {
        var text = ""
        var positions: [Position] = []

        init(_ marked: String) {
            var position = Position(line: 1, column: 1)
            for character in marked {
                if character == CFG01ConfigurationTests.marker {
                    positions.append(position)
                    continue
                }
                text.append(character)
                if character == "\n" {
                    position = Position(line: position.line + 1, column: 1)
                } else {
                    position.column += 1
                }
            }
        }
    }

    /// The required settings, then `settings` (written at the top level, indented by two spaces).
    private static func configuration(_ settings: String = "") -> String {
        """
        {
          version: 1,
          dataDirectory: "/var/lib/lisa-synthetic",
          timeZone: "America/New_York",
        \(settings)
        }
        """
    }

    private func parse(_ text: String) throws -> LisaConfiguration {
        try ConfigurationLoader.parse(text: text, sourceName: "synthetic.json5", homeDirectory: Self.home)
    }

    /// The error a configuration that must be refused gets, or `nil` (with an issue) when it was accepted.
    private func refusal(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> ConfigurationError? {
        do {
            _ = try ConfigurationLoader.parse(text: text, sourceName: "synthetic.json5", homeDirectory: Self.home)
            Issue.record("the configuration was accepted", sourceLocation: sourceLocation)
            return nil
        } catch {
            return error
        }
    }

    /// Checks that every external channel of `configuration` is a dry run, in the configuration and in the host
    /// settings composed from it, which decide whether the host builds a live transport.
    private func expectDryRun(_ configuration: LisaConfiguration, sourceLocation: SourceLocation = #_sourceLocation)
        throws
    {
        let modes = configuration.delivery.modes
        #expect(modes.email == .dryRun, sourceLocation: sourceLocation)
        #expect(modes.call == .dryRun, sourceLocation: sourceLocation)
        #expect(modes.push == .dryRun, sourceLocation: sourceLocation)
        #expect(!configuration.hasLiveDelivery, sourceLocation: sourceLocation)
        let host = try HostSettings(configuration: configuration, applicationVersion: "0.0.0-test")
        for delivery in [configuration.ownerSettings().delivery, host.ownerSettings.delivery] {
            #expect(delivery.emailMode == .dryRun, sourceLocation: sourceLocation)
            #expect(delivery.callMode == .dryRun, sourceLocation: sourceLocation)
            #expect(delivery.pushMode == .dryRun, sourceLocation: sourceLocation)
        }
    }

    // MARK: - The example

    /// The top-level settings the schema knows, as the loader lists them when it refuses an unknown one.
    private func knownTopLevelSettings() throws -> [String] {
        guard case .invalid(let issues)? = refusal(Self.configuration("  zzzzzzzzzzzzzzzzzzzz: 1,")) else { return [] }
        let fix = try #require(issues.first?.fix)
        let prefix = "remove it, or use one of: "
        #expect(fix.hasPrefix(prefix))
        let listed = fix.dropFirst(prefix.count)
        return listed.components(separatedBy: ", ").filter { $0 != "…" }
    }

    /// The keys written at the top level of `text`, whose members are indented by two spaces as in the example.
    private func topLevelKeys(in text: String) -> Set<String> {
        var keys: Set<String> = []
        for line in text.components(separatedBy: "\n") where line.hasPrefix("  ") {
            let rest = line.dropFirst(2)
            guard let first = rest.first, first.isLetter, let colon = rest.firstIndex(of: ":") else { continue }
            keys.insert(String(rest[..<colon]))
        }
        return keys
    }

    @Test("The repository's config.example.json5 reads and validates, covers every section and contacts no one")
    func exampleConfigurationValidates() throws {
        let configuration = try ConfigurationLoader.load(path: Self.examplePath, homeDirectory: Self.home)
        #expect(configuration.version == ConfigurationLoader.supportedVersion)
        #expect(configuration.sourceName == Self.examplePath)
        #expect(configuration.dataDirectory.hasPrefix("/"))

        // As its header promises, the example contacts no one: every channel is a dry run, email and calls are
        // disabled, every source is disabled, the model is the built-in deterministic provider, and the API listens on
        // this machine only.
        try expectDryRun(configuration)
        #expect(!configuration.delivery.emailEnabled)
        #expect(!configuration.delivery.callsEnabled)
        #expect(configuration.enabledSources.isEmpty)
        #expect(configuration.model.provider == .deterministic)
        #expect(configuration.api.isLoopbackOnly)

        // It is complete: every top-level setting of the schema is written in it, it describes each delivery adapter
        // and every kind of source, and its secrets are references to where they live.
        let text = try String(contentsOfFile: Self.examplePath, encoding: .utf8)
        let known = try knownTopLevelSettings()
        #expect(known.count >= 17)
        #expect(Set(known).isSubset(of: topLevelKeys(in: text)))
        #expect(!configuration.planning.windows.isEmpty)
        #expect(!configuration.planning.protectedTime.isEmpty)
        #expect(!configuration.delivery.approvedEmailAddresses.isEmpty)
        #expect(configuration.delivery.approvedPhoneNumber != nil)
        #expect(configuration.email != nil)
        #expect(configuration.calls != nil)
        let apns = try #require(configuration.notifications.apns)
        #expect(!apns.topics.isEmpty)
        #expect(configuration.model.endpoint != nil)
        #expect(configuration.model.modelIdentifier != nil)
        #expect(
            Set(configuration.sources.map(\.kind)) == [
                .mailbox, .calendarFeed, .newsFeed, .xAccount, .discordChannel, .localImport,
            ])
        let secrets = Set(configuration.referencedSecrets.map(\.path))
        let adapterSecrets = ["email.passwordSecret", "calls.authTokenSecret", "notifications.apns.signingKeySecret"]
        #expect(secrets.isSuperset(of: adapterSecrets))
    }

    // MARK: - Syntax errors

    /// A configuration text with a syntax error at its marker.
    struct SyntaxCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let marked: String
        /// Words of the problem the reader reports.
        let problem: String
        /// Whether the file is written with CRLF line endings.
        var crlf = false
    }

    static let syntaxCases: [SyntaxCase] = [
        SyntaxCase(
            testDescription: "a missing comma between two settings",
            marked: """
                {
                  version: 1,
                  dataDirectory: "/var/lib/lisa-synthetic"
                  ‸timeZone: "America/New_York",
                }
                """,
            problem: "expected ',' or '}'"),
        SyntaxCase(
            testDescription: "a missing comma in a file with CRLF line endings",
            marked: """
                {
                  version: 1,
                  dataDirectory: "/var/lib/lisa-synthetic"
                  ‸timeZone: "America/New_York",
                }
                """,
            problem: "expected ',' or '}'", crlf: true),
        SyntaxCase(
            testDescription: "a missing comma after text with an accented letter",
            marked: """
                {
                  version: 1,
                  dataDirectory: "/var/lib/café" ‸timeZone: "America/New_York",
                }
                """,
            problem: "expected ',' or '}'"),
        SyntaxCase(
            testDescription: "text in quotes that runs onto the next line",
            marked: """
                {
                  version: 1,
                  timeZone: "America/New_York,‸
                  dataDirectory: "/var/lib/lisa-synthetic",
                }
                """,
            problem: "cannot run onto the next line"),
        SyntaxCase(
            testDescription: "a setting written twice",
            marked: """
                {
                  version: 1,
                  timeZone: "America/New_York",
                  dataDirectory: "/var/lib/lisa-synthetic",
                  ‸timeZone: "Europe/London",
                }
                """,
            problem: "already appears at line 3, column 3"),
        SyntaxCase(
            testDescription: "an unquoted word as a value",
            marked: """
                {
                  version: 1,
                  dataDirectory: "/var/lib/lisa-synthetic",
                  timeZone: ‸America/New_York,
                }
                """,
            problem: "put text in quotes"),
        SyntaxCase(
            testDescription: "an object that is never closed",
            marked: """
                ‸{
                  version: 1,
                  dataDirectory: "/var/lib/lisa-synthetic",
                  timeZone: "America/New_York",
                  planning: { bufferMinutes: 10 },
                """,
            problem: "this object is not closed"),
    ]

    @Test(
        "A syntax error is reported at its line and column, whether read from text or from a file",
        arguments: syntaxCases)
    func syntaxErrorsNameTheirPosition(_ syntax: SyntaxCase) async throws {
        let marked = Marked(syntax.marked)
        let expected = try #require(marked.positions.first)
        let text = syntax.crlf ? marked.text.replacingOccurrences(of: "\n", with: "\r\n") : marked.text
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("config.json5")
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            var errors: [ConfigurationError] = []
            if let error = refusal(text) { errors.append(error) }
            do throws(ConfigurationError) {
                _ = try ConfigurationLoader.load(path: file.path, homeDirectory: Self.home)
                Issue.record("the configuration file was accepted")
            } catch {
                errors.append(error)
            }
            #expect(errors.count == 2)
            for error in errors {
                guard case .syntax(let line, let column, let problem) = error else {
                    Issue.record("not reported as a syntax error: \(error)")
                    continue
                }
                #expect(Position(line: line, column: column) == expected)
                #expect(problem.contains(syntax.problem))
                #expect(error.description.contains("line \(expected.line), column \(expected.column)"))
                // The message describes the problem without quoting the file's text.
                for written in ["lisa-synthetic", "New_York", "café", "London"] {
                    #expect(!problem.contains(written))
                }
            }
        }
    }

    // MARK: - Unknown keys

    @Test("Unknown keys are refused at their line and column, with the setting meant or the settings allowed")
    func unknownKeysAreRefused() throws {
        let marked = Marked(
            Self.configuration(
                """
                  ‸timezone: "Europe/London",
                  delivery: { modes: { ‸emial: "live" } },
                  api: { ‸authentication: false },
                  email: {
                    host: "smtp.example.com",
                    username: "lisa@example.com",
                    passwordSecret: "env:LISA_SMTP_PASSWORD",
                    fromAddress: "lisa@example.com",
                    ‸password: "synthetic-inline-password",
                  },
                """))
        guard case .invalid(let issues)? = refusal(marked.text) else {
            Issue.record("the unknown keys were not reported as invalid settings")
            return
        }
        // Every issue at once, in document order: the misspelled zone and live mode are reported rather than ignored,
        // there is no setting that turns API authentication off, and a password written inline is refused.
        let expected: [(path: String, problem: String, fix: String)] = [
            ("timezone", "is not a top-level setting", "did you mean timeZone?"),
            ("delivery.modes.emial", "is not a setting of delivery.modes", "did you mean email?"),
            ("api.authentication", "is not a setting of api", "remove it, or use one of: bindAddress"),
            ("email.password", "looks like a secret written into the configuration", "set passwordSecret"),
        ]
        #expect(issues.count == expected.count)
        #expect(marked.positions.count == expected.count)
        for (issue, (want, position)) in zip(issues, zip(expected, marked.positions)) {
            #expect(issue.path == want.path)
            #expect(issue.problem.contains(want.problem))
            #expect(issue.fix?.contains(want.fix) == true)
            #expect(Position(line: issue.line ?? 0, column: issue.column ?? 0) == position)
        }
        let description = ConfigurationError.invalid(issues).description
        #expect(!description.contains("synthetic-inline-password"))
        let first = marked.positions[0]
        #expect(description.contains("timezone (line \(first.line), column \(first.column))"))
    }

    // MARK: - Unsafe settings

    /// Settings that must be refused, with where and why.
    struct UnsafeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        /// Top-level settings added to the required ones; the marker is where the issue is reported.
        let settings: String
        let path: String
        let problem: String
        let fix: String?
        /// Text written into the configuration that the error must never repeat, such as a secret written inline.
        var written: String?
    }

    static let unsafeCases: [UnsafeCase] = [
        UnsafeCase(
            testDescription: "the API on every interface without TLS",
            settings: #"  api: { bindAddress: ‸"0.0.0.0" },"#, path: "api.bindAddress",
            problem: "is reachable from other machines", fix: "bind to 127.0.0.1, or configure api.tls"),
        UnsafeCase(
            testDescription: "the API for a reverse proxy on every interface",
            settings: #"  api: { bindAddress: ‸"0.0.0.0", tls: { mode: "reverseProxy" } },"#, path: "api.bindAddress",
            problem: "must be a loopback or private-network address when tls.mode is reverseProxy",
            fix: "bind to 127.0.0.1"),
        UnsafeCase(
            testDescription: "native TLS without its certificate and key",
            settings: #"  api: { bindAddress: "192.168.1.20", tls: { mode: ‸"native" } },"#, path: "api.tls.mode",
            problem: "native TLS needs api.tls.certificateSecret and api.tls.privateKeySecret",
            fix: "reference the PEM certificate chain and private key"),
        UnsafeCase(
            testDescription: "a password written into a secret setting",
            settings: """
                  email: {
                    host: "smtp.example.com",
                    username: "lisa@example.com",
                    passwordSecret: ‸"synthetic-inline-password",
                    fromAddress: "lisa@example.com",
                  },
                """,
            path: "email.passwordSecret",
            problem: "must be a secret reference: env:NAME, file:/absolute/path or keychain:service/account",
            fix: "never in this file", written: "synthetic-inline-password"),
        UnsafeCase(
            testDescription: "a credential in a feed's address",
            settings: """
                  sources: [
                    {
                      kind: "newsFeed",
                      key: "synthetic-feed",
                      url: ‸"https://feeds.example.com/rss?token=synthetic-token",
                    },
                  ],
                """,
            path: "sources[0].url", problem: "appears to carry a credential in its query", fix: "use urlSecret",
            written: "synthetic-token"),
        UnsafeCase(
            testDescription: "a calendar over plain http",
            settings: """
                  sources: [
                    {
                      kind: "calendarFeed",
                      key: "synthetic-calendar",
                      url: ‸"http://calendar.example.com/synthetic.ics",
                    },
                  ],
                """,
            path: "sources[0].url", problem: "must use https", fix: nil),
        UnsafeCase(
            testDescription: "live email without its adapter, enablement and approved address",
            settings: #"  delivery: { modes: { email: ‸"live" } },"#, path: "delivery.modes.email",
            problem: "live email delivery needs the email section", fix: #"set delivery.modes.email back to "dryRun""#),
        UnsafeCase(
            testDescription: "live calls without their adapter, enablement and approved number",
            settings: #"  delivery: { modes: { call: ‸"live" } },"#, path: "delivery.modes.call",
            problem: "live calls need the calls section", fix: #"set delivery.modes.call back to "dryRun""#),
        UnsafeCase(
            testDescription: "live pushes without an APNs provider",
            settings: #"  delivery: { modes: { push: ‸"live" } },"#, path: "delivery.modes.push",
            problem: "live push delivery needs notifications.apns", fix: #"set delivery.modes.push back to "dryRun""#),
        UnsafeCase(
            testDescription: "a model endpoint over plain http to another machine",
            settings: """
                  model: {
                    provider: "openAICompatible",
                    endpoint: ‸"http://models.example.com/v1",
                    modelIdentifier: "synthetic",
                  },
                """,
            path: "model.endpoint", problem: "must use https; plain http is allowed only to a loopback address",
            fix: nil),
        UnsafeCase(
            testDescription: "a remote model endpoint while data sharing is local only",
            settings: """
                  model: {
                    provider: "openAICompatible",
                    endpoint: ‸"https://models.example.com/v1",
                    modelIdentifier: "synthetic",
                  },
                """,
            path: "model.endpoint", problem: "is not an address on this machine or a private network",
            fix: "choose remoteMinimized"),
        UnsafeCase(
            testDescription: "Lisa sending from the owner's own address",
            settings: """
                  delivery: { approvedEmailAddresses: ["owner@example.com"] },
                  email: {
                    host: "smtp.example.com",
                    username: "lisa@example.com",
                    passwordSecret: "env:LISA_SMTP_PASSWORD",
                    fromAddress: ‸"owner@example.com",
                  },
                """,
            path: "email.fromAddress", problem: "is one of the owner's approved addresses",
            fix: "use the address of Lisa's dedicated mailbox"),
        UnsafeCase(
            testDescription: "Lisa reading the owner's own mailbox",
            settings: """
                  delivery: { approvedEmailAddresses: ["owner@example.com"] },
                  sources: [
                    {
                      kind: "mailbox",
                      key: "synthetic-mailbox",
                      host: "imap.example.com",
                      username: "lisa@example.com",
                      passwordSecret: "env:LISA_IMAP_PASSWORD",
                      mailboxAddress: ‸"owner@example.com",
                    },
                  ],
                """,
            path: "sources[0].mailboxAddress", problem: "Lisa reads only her own dedicated mailbox",
            fix: "create a separate mailbox for Lisa"),
        UnsafeCase(
            testDescription: "an approved phone number not in E.164 form",
            settings: #"  delivery: { approvedPhoneNumber: ‸"+1 555 555 0100" },"#,
            path: "delivery.approvedPhoneNumber",
            problem: "must be a phone number in E.164 form", fix: "for example +15555550100"),
    ]

    @Test(
        "An unsafe setting is refused at its line and column, saying what is wrong and what to change",
        arguments: unsafeCases)
    func unsafeSettingsAreRefused(_ unsafe: UnsafeCase) throws {
        let marked = Marked(Self.configuration(unsafe.settings))
        let position = try #require(marked.positions.first)
        guard case .invalid(let issues)? = refusal(marked.text) else {
            Issue.record("the setting was not reported as invalid")
            return
        }
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.path == unsafe.path)
        #expect(Position(line: issue.line ?? 0, column: issue.column ?? 0) == position)
        #expect(issue.problem.contains(unsafe.problem))
        if let fix = unsafe.fix {
            #expect(issue.fix?.contains(fix) == true)
        }
        let description = ConfigurationError.invalid(issues).description
        #expect(description.contains("\(unsafe.path) (line \(position.line), column \(position.column)): "))
        if let written = unsafe.written {
            #expect(!description.contains(written))
        }
    }

    // MARK: - Dry run by default

    /// Every delivery adapter configured, and email and calls enabled for the approved address and number, with
    /// `modes` written into the delivery section.
    private static func everyAdapter(modes: String) -> String {
        """
          delivery: {
            emailEnabled: true,
            callsEnabled: true,
            approvedEmailAddresses: ["owner@example.com"],
            approvedPhoneNumber: "+15555550100",
            \(modes)
          },
          email: {
            host: "smtp.example.com",
            username: "lisa@example.com",
            passwordSecret: "env:LISA_SMTP_PASSWORD",
            fromAddress: "lisa@example.com",
          },
          calls: {
            accountSID: "AC00000000000000000000000000000000",
            authTokenSecret: "env:LISA_TWILIO_AUTH_TOKEN",
            fromNumber: "+15555550199",
          },
          notifications: {
            apns: {
              environments: { development: true },
              signingKeySecret: "file:/etc/lisa-synthetic/apns-signing-key.p8",
              teamID: "ABCDE12345",
              keyID: "ABC123DEFG",
              topics: ["com.example.lisa.companion"],
            },
          },
        """
    }

    @Test("Without delivery modes every external delivery is a dry run, even with every adapter configured and enabled")
    func deliveryDefaultsToDryRun() throws {
        // Nothing about delivery at all: dry runs, email and calls disabled, no adapters.
        let minimal = try parse(Self.configuration())
        try expectDryRun(minimal)
        #expect(!minimal.delivery.emailEnabled)
        #expect(!minimal.delivery.callsEnabled)
        #expect(minimal.email == nil)
        #expect(minimal.calls == nil)
        #expect(minimal.notifications.apns == nil)

        // Every adapter configured and email and calls enabled (steps 1 and 3), with the modes left out, empty or null:
        // still dry runs, though the host has every adapter it would need.
        for modes in ["", "modes: {},", "modes: { email: null, call: null, push: null },"] {
            let configured = try parse(Self.configuration(Self.everyAdapter(modes: modes)))
            #expect(configured.delivery.emailEnabled)
            #expect(configured.delivery.callsEnabled)
            try expectDryRun(configured)
            let adapters = try HostSettings(configuration: configured, applicationVersion: "0.0.0-test")
                .deliveryAdapters
            #expect(adapters.smtp != nil)
            #expect(adapters.twilio != nil)
            #expect(adapters.apns != nil)
        }

        // Real delivery is the separate, deliberate step 4, channel by channel: setting email to live leaves calls and
        // pushes dry runs.
        let emailLive = try parse(Self.configuration(Self.everyAdapter(modes: #"modes: { email: "live" },"#)))
        #expect(emailLive.delivery.modes.email == .live)
        #expect(emailLive.delivery.modes.call == .dryRun)
        #expect(emailLive.delivery.modes.push == .dryRun)
        let delivery = try HostSettings(configuration: emailLive, applicationVersion: "0.0.0-test").ownerSettings
            .delivery
        #expect(delivery.emailMode == .live)
        #expect(delivery.callMode == .dryRun)
        #expect(delivery.pushMode == .dryRun)
    }
}
