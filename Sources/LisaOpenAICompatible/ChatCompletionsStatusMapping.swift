// Maps Chat Completions error statuses to the inference module's errors: credentials, limits, timeouts, unavailability.

import Foundation
import LisaHTTP
import LisaInference

/// Error statuses of `POST /chat/completions` (400, 401, 403, 404, 429, 500 and 503 in the official specification, and
/// what other servers commonly add). Configuration problems map to `unavailable`, so the items they affect wait for a
/// working model instead of being marked failed; summaries are Lisa's own words plus whitelisted identifiers.
enum ChatCompletionsStatusMapping {
    /// The request parameters whose rejection points at the dialect.
    static let dialectParameters: Set<String> = [
        "max_tokens", "max_completion_tokens", "temperature", "response_format", "stream",
    ]

    static func error(for response: HTTPResponse, now: Date) -> ModelError {
        let status = response.status
        let body = ChatCompletionsErrorBody.parse(response.body)
        switch status {
        case 401, 403:
            return .authentication
        case 408:
            return .timeout
        case 413:
            return .requestTooLarge
        case 429:
            return .rateLimited(retryAfter: RetryAfter.date(in: response, now: now))
        case 400, 422:
            return .unavailable(
                "the endpoint rejected the request as invalid or incompatible (HTTP \(status))\(hint(body))")
        case 404:
            return .unavailable(
                "the endpoint or the model was not found (HTTP 404); check the endpoint address and model identifier")
        case 300...399:
            return .unavailable(
                "the endpoint answered with a redirect (HTTP \(status)), which Lisa does not follow; configure the"
                    + " final address")
        case 500...599:
            return .unavailable("the endpoint reported a server error (HTTP \(status))")
        default:
            return .unavailable("the endpoint answered with an unexpected status (HTTP \(status))")
        }
    }

    /// Names the rejected parameter when it is one of the dialect's choices, so the owner knows what to change.
    static func hint(_ body: ChatCompletionsErrorBody) -> String {
        if let param = body.param, dialectParameters.contains(param) {
            return "; it did not accept \(param), so the request dialect needs adjusting"
        }
        if let param = body.param { return "; parameter \(param)" }
        return body.code.map { "; code \($0)" } ?? ""
    }
}
