// Adapter tests for L18, provider contracts, for the OpenAI-compatible model endpoint (MODEL-01, MODEL-04, SEC-02;
// D-41, D-42, D-44): the real model provider sends Chat Completions through the real libcurl client, with TLS verified
// against a synthetic authority made at run time, to a scripted HTTPS model server on loopback, an endpoint the owner
// may configure for a model on this machine. Success returns the reply's text and usage from exactly one request in
// the documented subset (model, messages, token limit, temperature, JSON mode, no streaming) with the API key from the
// secret store; an authentication failure (401), a server that stops answering (timeout) and a server limiting
// requests (429 with Retry-After) each become their own model error, so extraction waits instead of inventing
// anything. No model service is contacted.

import Foundation
import LisaAPIContract
import LisaCurl
import LisaInference
import LisaOpenAICompatible
import LisaSecrets
import LisaTime
import Testing

@Suite("L18 — OpenAI-compatible model contract", .tags(.adapter))
struct L18ModelContractTests {
    private static let keyVariable = "LISA_TEST_MODEL_KEY"
    private static let request = ModelRequest(
        messages: [
            ModelMessage(role: .system, content: "Answer with a JSON object."),
            ModelMessage(role: .user, content: "Synthetic message text."),
        ], maxOutputTokens: 200, temperature: 0, wantsJSON: true)

    private struct Setup {
        var server: ScriptedHTTPSServer
        var provider: OpenAICompatibleProvider
        var key: String
        var clock: ManualWallClock
    }

    /// `timeoutSeconds` is short only where the timeout is the point, so a busy machine cannot turn another case into
    /// one.
    private func withSetup(timeoutSeconds: Int = 10, _ body: (Setup) async throws -> Void) async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            try await ScriptedHTTPSServer.with(identity: identity) { server in
                let key = SyntheticDevice.randomHex(bytes: 24)
                let clock = TestTime.clock(at: TestTime.instant("2026-11-16T07:00", in: TestTime.newYork))
                let http = try CurlHTTPClient(configuration: .init(trustStorePath: identity.authorityFile.path))
                let provider = try OpenAICompatibleProvider(
                    configuration: OpenAICompatibleConfiguration(
                        endpoint: try #require(URL(string: "https://127.0.0.1:\(server.port)/v1")),
                        model: "synthetic-model", apiKey: .environment(Self.keyVariable),
                        requestTimeoutSeconds: timeoutSeconds),
                    secrets: EnvironmentSecretStore(environment: [Self.keyVariable: key]), http: http,
                    now: { clock.now() })
                try await body(Setup(server: server, provider: provider, key: key, clock: clock))
            }
        }
    }

    @Test("Fixture success: one Chat Completions request in the supported subset returns the reply's text and usage")
    func completes() async throws {
        try await withSetup { setup in
            let reply = #"{"items":[]}"#
            let body = try JSONSerialization.data(withJSONObject: [
                "id": "synthetic-1", "object": "chat.completion",
                "choices": [
                    ["index": 0, "message": ["role": "assistant", "content": reply], "finish_reason": "stop"]
                ],
                "usage": ["prompt_tokens": 12, "completion_tokens": 5],
            ])
            setup.server.script([.respond(status: 200, headers: ["Content-Type": "application/json"], body: body)])
            #expect(setup.provider.descriptor.location == .localNetwork)
            let response = try await setup.provider.complete(Self.request)
            #expect(response == ModelResponse(text: reply, finishReason: "stop", inputTokens: 12, outputTokens: 5))

            let requests = setup.server.requests
            #expect(requests.count == 1)
            let sent = try #require(requests.first)
            #expect(sent.method == .post)
            #expect(sent.path == "/v1/chat/completions")
            #expect(sent.header("Authorization") == "Bearer \(setup.key)")
            let json = try #require(try JSONSerialization.jsonObject(with: sent.body ?? Data()) as? [String: Any])
            #expect(Set(json.keys) == ["model", "messages", "max_tokens", "temperature", "response_format", "stream"])
            #expect(json["model"] as? String == "synthetic-model")
            #expect(json["stream"] as? Bool == false)
            #expect((json["response_format"] as? [String: String]) == ["type": "json_object"])
            let messages = try #require(json["messages"] as? [[String: String]])
            #expect(
                messages == [
                    ["role": "system", "content": "Answer with a JSON object."],
                    ["role": "user", "content": "Synthetic message text."],
                ])
        }
    }

    /// One way the endpoint fails a completion.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        var name: String
        var answer: ScriptedHTTPSServer.Answer
        /// The expected error, given the instant of the request.
        var expected: @Sendable (Date) -> ModelError
        var timeoutSeconds = 10
        var testDescription: String { name }
    }

    static let failureCases: [FailureCase] = [
        FailureCase(
            name: "authentication failure (401)", answer: .respond(status: 401), expected: { _ in .authentication }),
        FailureCase(
            name: "timeout: the server stops answering", answer: .hold, expected: { _ in .timeout }, timeoutSeconds: 2),
        FailureCase(
            name: "throttling (429 with Retry-After)", answer: .respond(status: 429, headers: ["Retry-After": "60"]),
            expected: { now in .rateLimited(retryAfter: now.addingTimeInterval(60)) }),
    ]

    @Test("Each failure becomes its own model error, and the API key never appears in it", arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        try await withSetup(timeoutSeconds: failure.timeoutSeconds) { setup in
            setup.server.script([failure.answer])
            let error = try await #require(throws: ModelError.self) {
                try await setup.provider.complete(Self.request)
            }
            #expect(error == failure.expected(setup.clock.now()))
            #expect(!error.description.contains(setup.key))
            #expect(setup.server.requests.count == 1)
        }
    }
}
