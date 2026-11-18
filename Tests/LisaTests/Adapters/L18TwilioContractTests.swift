// Adapter tests for L18, provider contracts, for outbound calls (CALL-01, REM-03, SEC-01; D-41, D-42): the real Twilio
// call transport runs against a scripted transport at the LisaHTTP boundary. Success creates exactly one call to the
// given number with inline, escaped TwiML (never a Url), authenticated with the auth token from the secret store; an
// authentication failure is a rejection; throttling (429, which Twilio documents as unprocessed) may be retried; and a
// timeout is "not sent" only when nothing was sent, but "unknown" once the request may have reached Twilio, because a
// call created twice would ring the owner twice. Results never carry the token, the numbers or the spoken text.
// Nothing reaches Twilio.

import Foundation
import LisaHTTP
import LisaPorts
import LisaSecrets
import LisaTime
import LisaTwilio
import Testing

@Suite("L18 — Twilio call contract", .tags(.adapter))
struct L18TwilioContractTests {
    private static let tokenVariable = "LISA_TEST_TWILIO_TOKEN"
    private static let fromNumber = "+15550199"
    private static let call = CallRequest(
        to: TestHost.ownerNumber, spokenText: "Synthetic filing due in 10 minutes & <it> needs you now.")

    private struct Setup {
        var client: ScriptedHTTPClient
        var transport: TwilioCallTransport
        var accountSID: String
        var token: String
        var clock: ManualWallClock
    }

    private func setup(_ steps: [ScriptedHTTPClient.Step]) -> Setup {
        let client = ScriptedHTTPClient(steps)
        let accountSID = "AC" + SyntheticDevice.randomHex(bytes: 16)
        let token = SyntheticDevice.randomHex(bytes: 16)
        let clock = TestTime.clock(at: TestTime.instant("2026-11-16T09:45", in: TestTime.newYork))
        let transport = TwilioCallTransport(
            settings: TwilioSettings(
                accountSID: accountSID, authTokenSecret: .environment(Self.tokenVariable), fromNumber: Self.fromNumber),
            secrets: EnvironmentSecretStore(environment: [Self.tokenVariable: token]), http: client, clock: clock)
        return Setup(client: client, transport: transport, accountSID: accountSID, token: token, clock: clock)
    }

    /// The fields of an `application/x-www-form-urlencoded` body.
    private static func form(_ body: Data?) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body ?? Data(), as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }

    @Test("Fixture success: one call to the given number speaks the escaped text, with the configured account")
    func createsOneCall() async throws {
        let sid = "CA" + SyntheticDevice.randomHex(bytes: 16)
        let setup = setup([.respond(status: 201, body: Data(#"{"sid":"\#(sid)","status":"queued"}"#.utf8))])
        let result = await setup.transport.place(Self.call)
        #expect(result == .accepted(providerReference: sid))
        let requests = setup.client.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == "POST")
        #expect(
            request.url.absoluteString == "https://api.twilio.com/2010-04-01/Accounts/\(setup.accountSID)/Calls.json")
        #expect(request.addresses == .publicOnly)
        #expect(request.redirects == .none)
        let authorization = try #require(request.headers.first { $0.name.lowercased() == "authorization" })
        #expect(authorization.isSensitive)
        #expect(authorization.value == "Basic " + Data("\(setup.accountSID):\(setup.token)".utf8).base64EncodedString())
        let fields = Self.form(request.body)
        #expect(Set(fields.keys) == ["To", "From", "Twiml"])
        #expect(fields["To"] == TestHost.ownerNumber)
        #expect(fields["From"] == Self.fromNumber)
        #expect(
            fields["Twiml"]
                == "<Response><Say>Synthetic filing due in 10 minutes &amp; &lt;it&gt; needs you now.</Say></Response>")
    }

    /// How Twilio answers, and what the transport must make of it.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        enum Expected: Sendable {
            case rejected
            case throttled(retryAfterSeconds: Double?)
            case notSent
            case unknown
        }

        var name: String
        var step: ScriptedHTTPClient.Step
        var expected: Expected
        var testDescription: String { name }
    }

    static let failureCases: [FailureCase] = [
        FailureCase(
            name: "authentication failure (401): rejected",
            step: .respond(status: 401, body: Data(#"{"code":20003,"message":"Authenticate","status":401}"#.utf8)),
            expected: .rejected),
        FailureCase(
            name: "throttling (429): retried after the provider's time",
            step: .respond(status: 429, headers: [HTTPHeader("Retry-After", "60")]),
            expected: .throttled(retryAfterSeconds: 60)),
        FailureCase(
            name: "throttling (429) without a retry time", step: .respond(status: 429),
            expected: .throttled(retryAfterSeconds: nil)),
        FailureCase(
            name: "timeout before the request was sent: not sent", step: .fail(.timedOut(requestSent: false)),
            expected: .notSent),
        FailureCase(
            name: "timeout after the request was sent: unknown, never placed again",
            step: .fail(.timedOut(requestSent: true)), expected: .unknown),
        FailureCase(
            name: "server error after the request: unknown", step: .respond(status: 500), expected: .unknown),
    ]

    @Test("Each failure gets the result that decides whether the call may be placed again", arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        let setup = setup([failure.step])
        let result = await setup.transport.place(Self.call)
        switch (failure.expected, result) {
        case (.rejected, .rejected(_, let invalidatesRecipient, _)):
            #expect(!invalidatesRecipient)
        case (.throttled(let seconds), .throttled(let retryAfter)):
            #expect(retryAfter == seconds.map { setup.clock.now().addingTimeInterval($0) })
        case (.notSent, .notSent), (.unknown, .unknown):
            break
        default:
            Issue.record("unexpected result \(result)")
        }
        let described = "\(result)"
        #expect(!described.contains(setup.token))
        #expect(!described.contains(TestHost.ownerNumber) && !described.contains(Self.fromNumber))
        #expect(!described.contains("Synthetic filing"))
        #expect(setup.client.requests.count == 1)
    }
}
