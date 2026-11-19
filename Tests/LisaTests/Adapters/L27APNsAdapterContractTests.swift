// Adapter tests for L27, the APNs adapter contract (NOTIFY-04, NOTIFY-03, NOTIFY-06, REM-03, SEC-01; plan §6.2, §6.4;
// D-38, D-42): the real APNs push transport runs against scripted transports at the LisaHTTP boundary, one per
// environment, so nothing contacts APNs or Apple. Acceptance is one HTTP/2-only POST to the registration's own fixed
// endpoint with the documented headers, a minimal payload and an ES256 provider token that openssl verifies against
// the synthetic signing key; invalid device tokens are rejected for good and invalidate the recipient; provider
// authentication errors regenerate the token once only when it expired; throttling and temporary failures are retried
// only after the provider's or Apple's delay; timeouts after sending are unknown and never resent; payloads stay
// within 4 KB; nothing is sent once the validity window ends, through the outbox as well; and HTTP/2 is checked rather
// than assumed.

import Foundation
import LisaAPIContract
import LisaAPNs
import LisaDomain
import LisaHTTP
import LisaHost
import LisaOwnerData
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime
import Testing

@Suite("L27 — APNs adapter contract", .tags(.adapter))
struct L27APNsAdapterContractTests {
    private static let deliveryID = "l27-delivery-0001"
    private static let collapseIdentity = "reminder:l27-reminder:2026-11-16T09:00"
    private static let topic = SyntheticDevice.companionBundleID

    private static func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// The real transport with one scripted client per environment and a synthetic signing key.
    private struct Harness {
        let transport: APNsPushTransport
        let development: ScriptedHTTPClient
        let production: ScriptedHTTPClient
        let clock: ManualWallClock
        let signingKey: String
        let token = SyntheticDevice.randomToken()
    }

    /// `signingKey` is what the secret store holds: the synthetic key by default, nothing when nil.
    private func harness(
        _ steps: [ScriptedHTTPClient.Step] = [], production: [ScriptedHTTPClient.Step] = [], http2Only: Bool = true,
        signingKey: (String) -> String? = { $0 }
    ) async throws -> Harness {
        let key = try await SyntheticSigningKey.generate()
        let development = ScriptedHTTPClient(steps, http2Only: http2Only)
        let productionClient = ScriptedHTTPClient(production, http2Only: http2Only)
        let clock = TestTime.clock(at: Self.at("08:00"))
        var environment: [String: String] = [:]
        if let held = signingKey(key) { environment[LivePush.signingKeyVariable] = held }
        let transport = try APNsPushTransport(
            settings: APNsSettings(
                teamID: LivePush.teamID, keyID: LivePush.keyID, signingKey: .environment(LivePush.signingKeyVariable),
                allowedTopics: [Self.topic], allowedEnvironments: [.development, .production]),
            secrets: EnvironmentSecretStore(environment: environment), clock: clock,
            clients: [.development: development, .production: productionClient])
        return Harness(
            transport: transport, development: development, production: productionClient, clock: clock,
            signingKey: key)
    }

    private static func message(
        to token: String, environment: APNsEnvironment = .development, category: NotificationCategoryID = .reminder,
        level: InterruptionLevel = .active, title: String? = nil, expiresAt: Date
    ) -> PushMessage {
        PushMessage(
            deviceToken: Sensitive(token), environment: environment, topic: topic,
            presentation: NotificationPresentation(
                titleKey: category.titleKey, bodyKey: category.bodyKey, itemTitle: title,
                categoryIdentifier: category.rawValue, threadIdentifier: "l27-thread", level: level,
                notificationID: "l27-notification-0001", subjectKind: "task", subjectID: "l27-task-0001",
                subjectRevision: 3),
            collapseID: collapseIdentity, deliveryID: deliveryID, expiresAt: expiresAt)
    }

    private static var apnsID: String { APNsIdentifiers.apnsID(forDelivery: deliveryID) }

    private static func accepted() -> ScriptedHTTPClient.Step {
        .respond(status: 200, headers: [HTTPHeader("apns-id", apnsID)], version: .http2)
    }

    /// APNs's JSON error body (`reason`, and for 410 a `timestamp` in milliseconds), over HTTP/2.
    private static func refused(
        _ status: Int, _ reason: String, timestamp: Date? = nil, headers: [HTTPHeader] = []
    ) -> ScriptedHTTPClient.Step {
        var object: [String: Any] = ["reason": reason]
        if let timestamp { object["timestamp"] = Int64(timestamp.timeIntervalSince1970 * 1000) }
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return .respond(status: status, headers: headers, body: body, version: .http2)
    }

    private static func epochSeconds(_ date: Date) -> String {
        String(Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    private static func providerToken(_ request: HTTPRequest) throws -> ProviderTokenCheck {
        let header = try #require(request.headers.first { $0.name.lowercased() == "authorization" })
        #expect(header.isSensitive)
        #expect(header.value.hasPrefix("bearer "))
        return try #require(ProviderTokenCheck(String(header.value.dropFirst("bearer ".count))))
    }

    @Test(
        "Acceptance: one HTTP/2-only POST to the registration's own endpoint, with the documented headers and payload",
        arguments: [APNsEnvironment.development, .production])
    func acceptance(_ environment: APNsEnvironment) async throws {
        try await ScratchDirectory.with { scratch in
            let harness = try await harness([Self.accepted()], production: [Self.accepted()])
            let expiresAt = Self.at("09:00").addingTimeInterval(0.75)
            let result = await harness.transport.push(
                Self.message(to: harness.token.uppercased(), environment: environment, expiresAt: expiresAt))
            #expect(result == .accepted(providerReference: Self.apnsID))

            let (used, other) =
                environment == .development
                ? (harness.development, harness.production) : (harness.production, harness.development)
            #expect(other.requests.isEmpty)
            let request = try #require(used.requests.first)
            #expect(used.requests.count == 1)
            let host = environment == .development ? "api.sandbox.push.apple.com" : "api.push.apple.com"
            #expect(request.url.absoluteString == "https://\(host)/3/device/\(harness.token)")
            #expect(request.method == "POST")
            #expect(request.version == .http2Only)
            #expect(request.redirects == .none)
            #expect(request.addresses == .publicOnly)
            #expect(request.header("apns-id") == Self.apnsID)
            #expect(request.header("apns-push-type") == "alert")
            #expect(request.header("apns-expiration") == Self.epochSeconds(expiresAt))
            #expect(request.header("apns-priority") == "10")
            #expect(request.header("apns-topic") == Self.topic)
            let collapse = try #require(request.header("apns-collapse-id"))
            #expect(collapse.count == 32 && collapse.allSatisfy(\.isHexDigit) && collapse == collapse.lowercased())
            #expect(collapse == APNsIdentifiers.collapseID(for: Self.collapseIdentity))
            let id = Self.apnsID
            #expect(id.count == 36 && id == id.lowercased() && !id.contains(Self.deliveryID))

            // The minimal payload: localization keys, category, thread, sound and level, and opaque identifiers.
            let body = try #require(request.body)
            #expect(body.count <= 4_096)
            let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(payload.keys) == ["aps", "lisa"])
            let aps = try #require(payload["aps"] as? [String: Any])
            #expect(Set(aps.keys) == ["alert", "category", "thread-id", "sound", "interruption-level"])
            #expect(aps["category"] as? String == "LISA_REMINDER")
            #expect(aps["interruption-level"] as? String == "active")
            let alert = try #require(aps["alert"] as? [String: Any])
            #expect(alert["title-loc-key"] as? String == "LISA_REMINDER_TITLE")
            #expect(alert["loc-key"] as? String == "LISA_REMINDER_BODY")
            #expect(alert["loc-args"] == nil)
            let lisa = try #require(PushPayload.lisaData(fromJSON: body))
            #expect(lisa.notificationID == "l27-notification-0001")
            #expect(lisa.subjectID == "l27-task-0001" && lisa.subjectRevision == 3)

            // The provider token is an ES256 JWT that openssl verifies with the synthetic key's public key.
            let token = try Self.providerToken(request)
            #expect(token.header["alg"] as? String == "ES256")
            #expect(token.header["kid"] as? String == LivePush.keyID)
            #expect(Set(token.header.keys) == ["alg", "kid"])
            #expect(token.claims["iss"] as? String == LivePush.teamID)
            #expect((token.claims["iat"] as? NSNumber)?.int64Value == Int64(Self.at("08:00").timeIntervalSince1970))
            #expect(Set(token.claims.keys) == ["iss", "iat"])
            #expect(try await token.verifies(withKey: harness.signingKey, in: scratch.url))
            // The check itself rejects the same signature over other claims: one second later.
            let later = #"{"iss":"\#(LivePush.teamID)","iat":\#(Int64(Self.at("08:00").timeIntervalSince1970) + 1)}"#
            let encoded = Data(later.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let forged = String(token.signingInput.prefix { $0 != "." }) + "." + encoded
            #expect(forged != token.signingInput)
            #expect(!(try await token.verifies(withKey: harness.signingKey, in: scratch.url, input: forged)))
        }
    }

    @Test(
        "The priority follows the category's actions and the interruption level",
        arguments: [
            (NotificationCategoryID.reminder, InterruptionLevel.active, "10", "active"),
            (.reminder, .timeSensitive, "10", "time-sensitive"),
            (.brief, .active, "5", "active"),
            (.eventProposal, .passive, "5", "passive"),
        ])
    func priority(_ category: NotificationCategoryID, _ level: InterruptionLevel, _ priority: String, _ sent: String)
        async throws
    {
        let harness = try await harness([Self.accepted()])
        _ = await harness.transport.push(
            Self.message(to: harness.token, category: category, level: level, expiresAt: Self.at("09:00")))
        let request = try #require(harness.development.requests.first)
        #expect(request.header("apns-priority") == priority)
        let payload = try #require(try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any])
        #expect((payload["aps"] as? [String: Any])?["interruption-level"] as? String == sent)
    }

    @Test("The provider token is reused for 50 minutes, then signed again with a later issue time")
    func providerTokenRefreshSchedule() async throws {
        try await ScratchDirectory.with { scratch in
            let harness = try await harness([Self.accepted(), Self.accepted(), Self.accepted()])
            for minutes in [0.0, 49, 51] {
                harness.clock.set(Self.at("08:00").addingTimeInterval(minutes * 60))
                let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("10:00")))
                #expect(result == .accepted(providerReference: Self.apnsID))
            }
            let tokens = try harness.development.requests.map(Self.providerToken)
            #expect(tokens.count == 3)
            #expect(tokens[0].signingInput == tokens[1].signingInput && tokens[0].signature == tokens[1].signature)
            #expect(tokens[2].signature != tokens[1].signature)
            #expect((tokens[2].claims["iat"] as? NSNumber)?.int64Value == Int64(Self.at("08:51").timeIntervalSince1970))
            #expect(try await tokens[2].verifies(withKey: harness.signingKey, in: scratch.url))
        }
    }

    @Test("An expired provider token is replaced once, and the push is retried once with the new token")
    func expiredProviderTokenIsReplacedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let harness = try await harness([Self.refused(403, "ExpiredProviderToken"), Self.accepted()])
            let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("09:00")))
            #expect(result == .accepted(providerReference: Self.apnsID))
            let requests = harness.development.requests
            #expect(requests.count == 2)
            let tokens = try requests.map(Self.providerToken)
            #expect(tokens[0].signature != tokens[1].signature)
            #expect(try await tokens[1].verifies(withKey: harness.signingKey, in: scratch.url))
            // Both attempts are the same notification for APNs.
            #expect(Set(requests.compactMap { $0.header("apns-id") }) == [Self.apnsID])
        }
    }

    /// A provider-authentication answer, and what the transport must make of it.
    struct AuthenticationCase: Sendable, CustomTestStringConvertible {
        var name: String
        var steps: [ScriptedHTTPClient.Step]
        /// Requests sent in total.
        var requests: Int
        /// True: rejected for good; false: throttled until the token may be updated again.
        var rejected: Bool
        var testDescription: String { name }
    }

    static let authenticationCases: [AuthenticationCase] = [
        AuthenticationCase(
            name: "403 InvalidProviderToken: a configuration rejection, never retried",
            steps: [refused(403, "InvalidProviderToken")], requests: 1, rejected: true),
        AuthenticationCase(
            name: "403 ExpiredProviderToken again with a new token: rejected after one retry",
            steps: [refused(403, "ExpiredProviderToken"), refused(403, "ExpiredProviderToken")], requests: 2,
            rejected: true),
        AuthenticationCase(
            name: "429 TooManyProviderTokenUpdates: the cached token is kept and the push waits",
            steps: [refused(429, "TooManyProviderTokenUpdates")], requests: 1, rejected: false),
    ]

    @Test("Provider-authentication errors are classified as documented", arguments: authenticationCases)
    func providerAuthenticationErrors(_ authentication: AuthenticationCase) async throws {
        let harness = try await harness(authentication.steps)
        let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("09:00")))
        #expect(harness.development.requests.count == authentication.requests)
        if authentication.rejected {
            guard case .rejected(_, let invalidatesRecipient, _) = result else {
                Issue.record("expected a rejection, got \(result)")
                return
            }
            #expect(!invalidatesRecipient)
        } else {
            // Apple allows a token update on one connection at most every 20 minutes.
            #expect(result == .throttled(retryAfter: Self.at("08:20")))
        }
    }

    @Test("A signing key that is missing or unusable sends nothing", arguments: [false, true])
    func unusableSigningKey(present: Bool) async throws {
        let harness = try await harness(
            [Self.accepted()], signingKey: { _ in present ? "-----BEGIN PRIVATE KEY-----\nnot a key\n" : nil })
        let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("09:00")))
        guard case .notSent(let reason) = result else {
            Issue.record("expected not sent, got \(result)")
            return
        }
        #expect(!reason.contains("not a key"))
        #expect(harness.development.requests.isEmpty)
    }

    /// An invalid-token answer.
    struct InvalidTokenCase: Sendable, CustomTestStringConvertible {
        var name: String
        var step: ScriptedHTTPClient.Step?
        var providerTimestamp: Date?
        var testDescription: String { name }
    }

    static let invalidTokenCases: [InvalidTokenCase] = [
        InvalidTokenCase(name: "400 BadDeviceToken", step: refused(400, "BadDeviceToken")),
        InvalidTokenCase(name: "400 DeviceTokenNotForTopic", step: refused(400, "DeviceTokenNotForTopic")),
        InvalidTokenCase(
            name: "410 Unregistered, with Apple's timestamp",
            step: refused(410, "Unregistered", timestamp: at("07:30")), providerTimestamp: at("07:30")),
        InvalidTokenCase(name: "410 ExpiredToken", step: refused(410, "ExpiredToken")),
        InvalidTokenCase(name: "a token that is not hexadecimal, never sent", step: nil),
    ]

    @Test("Invalid device tokens are rejected for good and invalidate the recipient", arguments: invalidTokenCases)
    func invalidDeviceTokens(_ invalid: InvalidTokenCase) async throws {
        let harness = try await harness(invalid.step.map { [$0] } ?? [])
        let token = invalid.step == nil ? "not-a-hex-token" : harness.token
        let result = await harness.transport.push(Self.message(to: token, expiresAt: Self.at("09:00")))
        guard case .rejected(let reason, let invalidatesRecipient, let timestamp) = result else {
            Issue.record("expected a rejection, got \(result)")
            return
        }
        #expect(invalidatesRecipient)
        #expect(timestamp == invalid.providerTimestamp)
        #expect(!reason.contains(token))
        #expect(harness.development.requests.count == (invalid.step == nil ? 0 : 1))
    }

    /// A throttling or temporary-failure answer, and when a retry is allowed (seconds after 08:00).
    struct RetryCase: Sendable, CustomTestStringConvertible {
        var name: String
        var step: ScriptedHTTPClient.Step
        /// nil: the result is "not sent", which the outbox retries with its own backoff.
        var throttled: Bool?
        var retryAfterSeconds: Double?
        var testDescription: String { name }
    }

    static let retryCases: [RetryCase] = [
        RetryCase(
            name: "429 TooManyRequests with Retry-After",
            step: refused(429, "TooManyRequests", headers: [HTTPHeader("Retry-After", "120")]), throttled: true,
            retryAfterSeconds: 120),
        RetryCase(
            name: "429 TooManyRequests without a retry time", step: refused(429, "TooManyRequests"), throttled: true),
        RetryCase(
            name: "500 InternalServerError: no sooner than 15 minutes", step: refused(500, "InternalServerError"),
            throttled: false, retryAfterSeconds: 900),
        RetryCase(
            name: "503 ServiceUnavailable asking for an hour",
            step: refused(503, "ServiceUnavailable", headers: [HTTPHeader("Retry-After", "3600")]), throttled: false,
            retryAfterSeconds: 3_600),
        RetryCase(
            name: "503 Shutdown asking for a minute: still 15 minutes",
            step: refused(503, "Shutdown", headers: [HTTPHeader("Retry-After", "60")]), throttled: false,
            retryAfterSeconds: 900),
        RetryCase(name: "400 IdleTimeout: not accepted, may be retried", step: refused(400, "IdleTimeout")),
    ]

    @Test("Throttling and temporary failures allow a retry only after the documented delay", arguments: retryCases)
    func throttlingAndTemporaryFailures(_ retry: RetryCase) async throws {
        let harness = try await harness([retry.step])
        let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("10:00")))
        let expected = retry.retryAfterSeconds.map { Self.at("08:00").addingTimeInterval($0) }
        switch (retry.throttled, result) {
        case (true?, .throttled(let retryAfter)):
            #expect(retryAfter == expected)
        case (false?, .temporarilyUnavailable(_, let retryAfter)):
            #expect(retryAfter == expected)
        case (nil, .notSent):
            break
        default:
            Issue.record("unexpected result \(result)")
        }
        #expect(harness.development.requests.count == 1)
    }

    /// A transport failure, and whether the push may have reached APNs.
    struct TransportCase: Sendable, CustomTestStringConvertible {
        var failure: HTTPFailure
        /// "unknown" (never resent), "notSent" (may be retried) or "rejected" (a capability failure).
        var expected: String
        var testDescription: String { "\(failure) → \(expected)" }
    }

    static let transportCases: [TransportCase] = [
        TransportCase(failure: .timedOut(requestSent: true), expected: "unknown"),
        TransportCase(failure: .connectionLost(requestSent: true, "reset by peer"), expected: "unknown"),
        TransportCase(failure: .timedOut(requestSent: false), expected: "notSent"),
        TransportCase(failure: .notSent("connection refused"), expected: "notSent"),
        TransportCase(failure: .untrustedServer("unknown authority"), expected: "notSent"),
        TransportCase(failure: .http2Unavailable, expected: "notSent"),
        TransportCase(failure: .unsupported("no HTTP/2"), expected: "rejected"),
    ]

    @Test("A timeout or lost connection after sending is unknown and never resent", arguments: transportCases)
    func timeoutsAndLostConnections(_ transport: TransportCase) async throws {
        let harness = try await harness([.fail(transport.failure)])
        let result = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("09:00")))
        switch (transport.expected, result) {
        case ("unknown", .unknown), ("notSent", .notSent):
            break
        case ("rejected", .rejected(let reason, let invalidatesRecipient, _)):
            #expect(reason.hasPrefix("capability"))
            #expect(!invalidatesRecipient)
        default:
            Issue.record("unexpected result \(result)")
        }
        #expect(harness.development.requests.count == 1)
    }

    @Test("Payloads stay within 4 KB: a long opted-in title is shortened, and 413 is rejected without a retry")
    func payloadLimits() async throws {
        let title = String(repeating: "Synthetic très long title ", count: 250)
        let harness = try await harness([Self.accepted(), Self.refused(413, "PayloadTooLarge")])
        let accepted = await harness.transport.push(
            Self.message(to: harness.token, title: title, expiresAt: Self.at("09:00")))
        #expect(accepted == .accepted(providerReference: Self.apnsID))
        let body = try #require(harness.development.requests.first?.body)
        #expect(body.count <= 4_096)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let alert = try #require((payload["aps"] as? [String: Any])?["alert"] as? [String: Any])
        #expect(alert["loc-key"] as? String == "LISA_REMINDER_BODY_TITLED")
        let shortened = try #require((alert["loc-args"] as? [String])?.first)
        #expect(shortened.hasSuffix("\u{2026}"))
        #expect(title.hasPrefix(String(shortened.dropLast())))
        #expect(shortened.count > 100)

        let refused = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("09:00")))
        guard case .rejected(_, let invalidatesRecipient, _) = refused else {
            Issue.record("expected a rejection, got \(refused)")
            return
        }
        #expect(!invalidatesRecipient)
        #expect(harness.development.requests.count == 2)
    }

    @Test("Expiry: nothing is sent once the validity window has ended, and APNs never keeps a push past 30 days")
    func expiry() async throws {
        let harness = try await harness([Self.accepted()])
        let expired = await harness.transport.push(Self.message(to: harness.token, expiresAt: Self.at("08:00")))
        guard case .rejected(let reason, _, _) = expired else {
            Issue.record("expected a rejection, got \(expired)")
            return
        }
        #expect(reason.contains("validity window"))
        #expect(harness.development.requests.isEmpty)

        let distant = Self.at("08:00").addingTimeInterval(60 * 86_400)
        _ = await harness.transport.push(Self.message(to: harness.token, expiresAt: distant))
        let request = try #require(harness.development.requests.first)
        #expect(
            request.header("apns-expiration") == Self.epochSeconds(Self.at("08:00").addingTimeInterval(30 * 86_400)))
    }

    @Test("HTTP/2 is checked, never assumed: a transport or a response without it is a capability failure")
    func http2IsChecked() async throws {
        let incapable = try await harness([Self.accepted()], http2Only: false)
        let refused = await incapable.transport.push(Self.message(to: incapable.token, expiresAt: Self.at("09:00")))
        guard case .rejected(let reason, _, _) = refused else {
            Issue.record("expected a capability rejection, got \(refused)")
            return
        }
        #expect(reason.hasPrefix("capability"))
        #expect(incapable.development.requests.isEmpty)

        let downgraded = try await harness([.respond(status: 200, version: .http11)])
        let result = await downgraded.transport.push(Self.message(to: downgraded.token, expiresAt: Self.at("09:00")))
        guard case .rejected(let downgradeReason, _, _) = result else {
            Issue.record("a response over HTTP/1.1 must not count as accepted: \(result)")
            return
        }
        #expect(downgradeReason.contains("HTTP/1.1"))
    }

    @Test("A host whose live push channel cannot send HTTP/2-only requests refuses to start")
    func hostRefusesPushWithoutHTTP2() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            var testHost = TestHost(scratch: scratch, now: Self.at("08:00"))
            live.configure(&testHost)
            let incapable = ScriptedHTTPClient(http2Only: false)
            let network = HostNetwork(
                makeHTTPClient: { purpose in
                    if case .apns = purpose { return incapable }
                    throw TestHost.NetworkRefused(purpose: purpose)
                }, mailTrustStorePath: nil, library: TestHost.offlineNetwork.library)
            let error = #expect(throws: HostError.self) {
                try LisaHost.open(
                    settings: testHost.settings,
                    platform: HostPlatform(
                        clock: testHost.clock,
                        secrets: EnvironmentSecretStore(environment: [LivePush.signingKeyVariable: live.signingKey]),
                        mode: "test", network: network))
            }
            guard case .liveDeliveryUnavailable(let channel, _)? = error else {
                Issue.record("expected the push channel to be unavailable, got \(String(describing: error))")
                return
            }
            #expect(channel == "push")
            #expect(incapable.requests.isEmpty)
        }
    }

    @Test("Through the outbox, a server error waits 15 minutes, and no push is sent once its validity window ends")
    func outboxHonorsDelayAndValidity() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush(
                apns: ScriptedAPNsClient(otherwise: .refused(status: 503, reason: "ServiceUnavailable")))
            var owner = TestHost.owner()
            owner.notifications.notifyBriefAvailability = false
            var testHost = TestHost(scratch: scratch, now: Self.at("08:00"), owner: owner)
            live.configure(&testHost)
            let host = try live.open(testHost)
            let phone = try TestHost.pairPhone(on: host)
            let token = try #require(try LivePush.token(of: phone.rawValue, in: host))
            // Every reminder offset has passed, so the task gets one reminder now, valid until its deadline at 08:20.
            let task = try host.application.createTask(
                TaskDraft(title: "Synthetic signature", deadline: SyntheticTask.due(Self.at("08:20"))), by: .localOwner)
            await host.runtime.runOnce()
            let notification = try #require(try TaskNotifications.occurrences(of: task.id, in: host).first)
            let pushes = { live.apns.exchanges(to: token, about: notification.id.rawValue) }
            #expect(pushes().count == 1)
            let waiting = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(waiting.state == .pending)
            #expect(waiting.nextAttemptAt >= Self.at("08:15"))

            for (time, sent) in [("08:10", 1), ("08:16", 2), ("08:25", 2), ("08:40", 2)] {
                testHost.clock.set(Self.at(time))
                await host.runtime.runOnce()
                #expect(pushes().count == sent, "at \(time)")
            }
            let failed = try #require(try host.application.record(Delivery.self, id: waiting.id))
            #expect(failed.state == .failed)
            #expect(failed.stateReason?.contains("no retry is possible before it expires") == true)
            // Both attempts asked APNs to drop the push at the deadline, as one notification.
            #expect(Set(pushes().compactMap { $0.header("apns-expiration") }) == [Self.epochSeconds(Self.at("08:20"))])
            #expect(Set(pushes().compactMap { $0.header("apns-id") }).count == 1)
            host.close()
        }
    }
}
