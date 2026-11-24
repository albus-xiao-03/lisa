// The controlled servers' classification of every request they receive (plan §10.8): identity-only, mailbox read,
// calendar read or send; model requests and calls are counted under their own classes.

/// What a request was, as the controlled servers classify it.
public enum ControlledRequestClass: String, Sendable, CaseIterable {
    case identityOnly = "identity-only"
    case mailboxRead = "mailbox-read"
    case calendarRead = "calendar-read"
    case send
    case modelRequest = "model-request"
    case call
    case control
    case other

    /// Classifies an HTTP request by its method and path, in the shapes of the services Lisa talks to.
    public static func classify(method: String, path: String) -> ControlledRequestClass {
        let path = path.split(separator: "?").first.map(String.init) ?? path
        if path.hasPrefix("/_controlled/") { return .control }
        if method == "POST", path.hasPrefix("/3/device/") { return .send }
        if method == "POST",
            path == "/v1/chat/completions" || path == "/v1/responses" || path == "/v1/messages"
                || path == "/api/chat"
        {
            return .modelRequest
        }
        if method == "POST", path.hasPrefix("/2010-04-01/Accounts/"), path.hasSuffix("/Calls.json") { return .call }
        if path == "/v1.0/me" || path == "/gmail/v1/users/me/profile" || path == "/oauth2/v3/userinfo" {
            return .identityOnly
        }
        if path.hasPrefix("/gmail/v1/users/me/messages") || path.hasPrefix("/v1.0/me/messages") { return .mailboxRead }
        if path.hasPrefix("/calendar/v3/") || path.hasPrefix("/v1.0/me/calendars") { return .calendarRead }
        if method == "POST", path.hasPrefix("/gmail/v1/users/me/messages/send") || path == "/v1.0/me/sendMail" {
            return .send
        }
        return .other
    }
}
