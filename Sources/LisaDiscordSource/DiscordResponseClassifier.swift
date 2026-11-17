// Classifies Discord API responses that carry no messages: HTTP status, JSON error codes and rate limits.

import Foundation
import LisaHTTP
import LisaPorts

/// Turns Discord's error responses into connector failures
/// (https://docs.discord.com/developers/topics/opcodes-and-status-codes.md#http). Summaries are Lisa's own words; from
/// the response only the status, the numeric error code and rate-limit values are used.
enum DiscordResponseClassifier {
    static func failure(for response: HTTPResponse, now: Date) -> ConnectorError {
        let body = DiscordErrorBody.parse(response.body)
        let status = response.status
        let code = body.code.map { ", code \($0)" } ?? ""
        switch status {
        case 400:
            return ConnectorError(.unsupported, "Discord did not accept Lisa's request (HTTP 400\(code))")
        case 401:
            return ConnectorError(.authentication, "Discord rejected the bot token (HTTP 401\(code))")
        case 403:
            return ConnectorError(
                .permissionDenied,
                "the bot cannot read this channel (HTTP 403\(code)); it needs the View Channel and Read Message History"
                    + " permissions there")
        case 404:
            return ConnectorError(
                .configuration,
                "Discord does not know this channel, or the bot cannot see it (HTTP 404\(code)); check the channel ID"
                    + " and that the bot is in the server")
        case 429:
            let headers = DiscordRateLimitHeaders(response)
            let scope = body.global == true || headers.isGlobal ? "the bot's global" : "this channel's"
            return ConnectorError(
                .rateLimited, "Discord is rate limiting \(scope) requests (HTTP 429)",
                retryAfter: DiscordRateLimitHeaders.retryDate(for: response, body: body, now: now))
        case 500...599:
            return ConnectorError(
                .network, "Discord is temporarily unavailable (HTTP \(status))",
                retryAfter: RetryAfter.date(in: response, now: now))
        case 300...399:
            return ConnectorError(
                .network, "Discord answered with a redirect (HTTP \(status)), which Lisa does not follow")
        default:
            return ConnectorError(.unsupported, "Discord answered with an unexpected status (HTTP \(status)\(code))")
        }
    }
}
