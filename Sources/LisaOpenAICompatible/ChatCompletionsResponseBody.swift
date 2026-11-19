// Decodes a Chat Completions response defensively and turns it into a model response, or says why it is unusable.

import Foundation
import LisaInference

/// The response subset Lisa reads (`CreateChatCompletionResponse`): `choices[].message.content` (a string or null),
/// `refusal`, `finish_reason`, and `usage.prompt_tokens` and `usage.completion_tokens`. Only `choices` is required;
/// members local servers often leave out (`id`, `object`, `created`, `logprobs`, `usage`) are optional, and members of
/// an unexpected type are treated as absent.
struct ChatCompletionsResponseBody: Hashable, Sendable {
    struct Choice: Hashable, Sendable {
        var index: Int?
        var message: Message?
        var finishReason: String?
    }

    struct Message: Hashable, Sendable {
        var content: String?
        var refusal: String?
        var hasToolCalls: Bool
    }

    var choices: [Choice]
    var promptTokens: Int?
    var completionTokens: Int?

    /// The finish reasons of the official specification; servers may send others.
    static let documentedFinishReasons: Set<String> = [
        "stop", "length", "tool_calls", "content_filter", "function_call",
    ]
    /// The most choices read.
    static let maxChoices = 8

    /// Decodes `data`; anything that is not a Chat Completions object is an invalid response.
    static func decode(_ data: Data) throws(ModelError) -> ChatCompletionsResponseBody {
        do {
            return try JSONDecoder().decode(ChatCompletionsResponseBody.self, from: data)
        } catch {
            throw ModelError.invalidResponse("the endpoint's reply was not a Chat Completions object")
        }
    }

    /// The first choice's message as a model response. A reply without text says why: a refusal, the endpoint's
    /// content filter, an unrequested tool call, or nothing at all. Text is returned as sent; its size, JSON shape and
    /// content are validated by the caller (`ExtractionValidator`).
    func modelResponse() throws(ModelError) -> ModelResponse {
        guard let choice = choices.first(where: { $0.index == 0 }) ?? choices.first else {
            throw ModelError.invalidResponse("the endpoint's reply has no choices")
        }
        let finish = choice.finishReason.flatMap(Self.finishReason)
        if let content = choice.message?.content, !content.isEmpty {
            return ModelResponse(
                text: content, finishReason: finish, inputTokens: promptTokens, outputTokens: completionTokens)
        }
        if let refusal = choice.message?.refusal, !refusal.isEmpty {
            throw ModelError.invalidResponse("the model declined to answer")
        }
        if finish == "content_filter" {
            throw ModelError.invalidResponse("the endpoint's content filter withheld the answer")
        }
        if choice.message?.hasToolCalls == true || finish == "tool_calls" || finish == "function_call" {
            throw ModelError.invalidResponse("the model answered with a tool call, which Lisa never requests")
        }
        throw ModelError.invalidResponse("the endpoint's reply has no message text")
    }

    /// A finish reason of lowercase letters and underscores, at most 32 bytes; anything else is dropped.
    static func finishReason(_ text: String) -> String? {
        guard (1...32).contains(text.utf8.count), text.utf8.allSatisfy({ (0x61...0x7A).contains($0) || $0 == 0x5F })
        else { return nil }
        return text
    }
}

extension ChatCompletionsResponseBody: Decodable {
    private enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    private enum ChoiceKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }

    private enum MessageKeys: String, CodingKey {
        case content
        case refusal
        case toolCalls = "tool_calls"
        case functionCall = "function_call"
    }

    private enum UsageKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .choices)
        var choices: [Choice] = []
        while !list.isAtEnd, choices.count < Self.maxChoices {
            let choice = try list.nestedContainer(keyedBy: ChoiceKeys.self)
            var message: Message?
            if let body = try? choice.nestedContainer(keyedBy: MessageKeys.self, forKey: .message) {
                let toolCalls =
                    ((try? body.decodeNil(forKey: .toolCalls)) == false)
                    || ((try? body.decodeNil(forKey: .functionCall)) == false)
                message = Message(
                    content: try? body.decodeIfPresent(String.self, forKey: .content),
                    refusal: try? body.decodeIfPresent(String.self, forKey: .refusal), hasToolCalls: toolCalls)
            }
            choices.append(
                Choice(
                    index: try? choice.decodeIfPresent(Int.self, forKey: .index), message: message,
                    finishReason: try? choice.decodeIfPresent(String.self, forKey: .finishReason)))
        }
        self.choices = choices
        let usage = try? container.nestedContainer(keyedBy: UsageKeys.self, forKey: .usage)
        promptTokens = (try? usage?.decodeIfPresent(Int.self, forKey: .promptTokens)).flatMap { $0 >= 0 ? $0 : nil }
        completionTokens = (try? usage?.decodeIfPresent(Int.self, forKey: .completionTokens)).flatMap {
            $0 >= 0 ? $0 : nil
        }
    }
}
