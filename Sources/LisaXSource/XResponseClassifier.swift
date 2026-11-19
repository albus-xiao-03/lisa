// Classifies X API responses that carry no usable posts: HTTP status, problem types and rate limits.

import Foundation
import LisaHTTP
import LisaPorts

/// Turns X's error responses into connector failures (https://docs.x.com/x-api/fundamentals/response-codes-and-errors.md).
/// Summaries are Lisa's own words; from the response only the status, problem types and whitelisted parameter names
/// are used.
enum XResponseClassifier {
    /// The failure for a response whose status is not 200.
    static func failure(for response: HTTPResponse, now: Date) -> ConnectorError {
        let problems = XProblemDetails.parse(response.body)
        let status = response.status
        switch status {
        case 400:
            let summary = "X did not accept Lisa's request (HTTP 400\(parameters(problems)))" + fieldsNote(problems)
            return ConnectorError(.unsupported, summary)
        case 401:
            return ConnectorError(.authentication, "X rejected the bearer token (HTTP 401)")
        case 403:
            return forbidden(problems, status: "HTTP 403")
        case 404:
            return ConnectorError(.configuration, "X did not find the account (HTTP 404); check the user ID")
        case 429:
            return rateLimited(
                problems, status: "HTTP 429", retryAfter: XRateLimitHeaders.retryDate(for: response, now: now))
        case 500...599:
            return ConnectorError(
                .network, "X is temporarily unavailable (HTTP \(status))",
                retryAfter: RetryAfter.date(in: response, now: now))
        case 300...399:
            return ConnectorError(.network, "X answered with a redirect (HTTP \(status)), which Lisa does not follow")
        default:
            return ConnectorError(.unsupported, "X answered with an unexpected status (HTTP \(status))")
        }
    }

    /// The failure for a successful response that carries errors and no posts, such as a deleted, suspended or
    /// protected account.
    static func failure(forErrorsWithoutPosts problems: XProblemDetails, response: HTTPResponse, now: Date)
        -> ConnectorError
    {
        if problems.contains("resource-not-found") {
            return ConnectorError(.configuration, "X reports that the account does not exist; check the user ID")
        }
        if problems.contains("usage-capped") || problems.contains("rate-limit-exceeded") || problems.codes.contains(88)
        {
            return rateLimited(
                problems, status: "reported in the response",
                retryAfter: XRateLimitHeaders.retryDate(for: response, now: now))
        }
        if problems.contains("resource-unavailable") {
            return ConnectorError(.permissionDenied, "X reports that the account is unavailable, for example suspended")
        }
        if problems.contains("not-authorized-for-resource") || problems.contains("client-forbidden")
            || problems.contains("disallowed-resource")
        {
            return forbidden(problems, status: "reported in the response")
        }
        return ConnectorError(.partial, "X returned errors instead of posts")
    }

    /// 403: the app's access level, or the account's visibility.
    private static func forbidden(_ problems: XProblemDetails, status: String) -> ConnectorError {
        if problems.contains("not-authorized-for-resource") || problems.contains("disallowed-resource") {
            return ConnectorError(
                .permissionDenied,
                "X does not allow app-only access to this account's posts, for example because they are protected"
                    + " (\(status))")
        }
        if problems.contains("client-forbidden") {
            return ConnectorError(
                .capabilityDenied,
                "the X developer app's access does not include reading posts (\(status), client-forbidden)")
        }
        return ConnectorError(
            .capabilityDenied, "X denied the request (\(status)); the app's access may not include this endpoint")
    }

    /// 429 means either the rate limit or the usage cap ("Rate limit or usage cap exceeded").
    private static func rateLimited(_ problems: XProblemDetails, status: String, retryAfter: Date?) -> ConnectorError {
        if problems.contains("usage-capped") {
            return ConnectorError(
                .rateLimited,
                "X reports that the app's usage cap is used up (\(status), usage-capped); reading resumes when the cap"
                    + " resets or is raised",
                retryAfter: retryAfter)
        }
        return ConnectorError(
            .rateLimited, "X's rate limit for this app is exceeded (\(status))", retryAfter: retryAfter)
    }

    private static func parameters(_ problems: XProblemDetails) -> String {
        let names = Array(Set(problems.parameters)).sorted().prefix(3)
        return names.isEmpty ? "" : ", parameter " + names.joined(separator: ", ")
    }

    /// Points at the documented naming conflict when X objects to the fields or expansions parameter.
    private static func fieldsNote(_ problems: XProblemDetails) -> String {
        let requested: Set<String> = [XPostFields.parameterName, XPostFields.expansionsParameterName]
        guard !requested.isDisjoint(with: problems.parameters) else { return "" }
        return "; X's documentation disagrees on the fields parameter's name (tweet.fields or post.fields), which needs"
            + " a live check"
    }
}
