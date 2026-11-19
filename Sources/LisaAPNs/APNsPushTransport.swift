// The production APNs push transport (NOTIFY-04): token-authenticated alert pushes over HTTP/2 with full TLS
// validation, to the fixed endpoint of each registration's own environment, with every outcome classified.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaSecrets
import LisaTime

/// Sends ordinary APNs alert notifications (S10–S14).
///
/// One HTTP client per environment is injected. LisaHost gives each environment its own libcurl client so that each
/// keeps one long-lived HTTP/2 connection, and this transport sends one request at a time per environment. A token
/// is only ever sent to its own environment's fixed endpoint, and a push is reported as accepted only when APNs
/// answered 200 over HTTP/2. Refusals before sending (an environment or topic that is not configured, a malformed
/// token, an expired notification, a payload that cannot be built, a transport without HTTP/2-only support or an
/// unavailable signing key) are classified results, not crashes.
public final class APNsPushTransport: PushTransport {
    public let mode = DeliveryMode.live
    public let settings: APNsSettings
    private let clock: any WallClock
    private let connections: [APNsEnvironment: APNsEnvironmentConnection]

    /// Creates the transport. Nothing is sent and no secret is read here.
    ///
    /// - Parameters:
    ///   - settings: validated first; invalid settings throw, and no transport exists.
    ///   - secrets: resolves the signing key each time a provider token is signed.
    ///   - clock: the clock for token ages, expirations and retry times.
    ///   - clients: one HTTP client for each allowed environment; clients for other environments are ignored.
    public init(
        settings: APNsSettings, secrets: any SecretStore, clock: any WallClock,
        clients: [APNsEnvironment: any HTTPClient]
    ) throws(APNsConfigurationError) {
        try settings.validate()
        var connections: [APNsEnvironment: APNsEnvironmentConnection] = [:]
        for environment in APNsEnvironment.allCases {
            guard let credentials = settings.credentials[environment] else { continue }
            guard let client = clients[environment] else { throw .missingHTTPClient(environment) }
            connections[environment] = APNsEnvironmentConnection(
                endpoint: APNsEndpoint(environment), client: client,
                tokens: APNsProviderTokenCache(teamID: settings.teamID, credentials: credentials, secrets: secrets))
        }
        self.settings = settings
        self.clock = clock
        self.connections = connections
    }

    /// Each allowed environment's fixed endpoint and run-time HTTP/2 capability, for `lisa doctor`.
    public var environmentStatus: [APNsEnvironmentStatus] {
        APNsEnvironment.allCases.compactMap { environment in
            guard let connection = connections[environment] else { return nil }
            let capabilities = connection.client.capabilities
            return APNsEnvironmentStatus(
                environment: environment, endpoint: connection.endpoint.origin,
                keyID: connection.tokens.credentials.keyID, http2Only: capabilities.http2Only,
                transportSummary: capabilities.summary)
        }
    }

    public func push(_ message: PushMessage) async -> TransportResult {
        switch prepare(message) {
        case .refused(let result):
            return result
        case .ready(let prepared):
            return await prepared.connection.gate.run { await self.send(prepared) }
        }
    }

    // MARK: - Preparation (no network I/O)

    private enum Preparation {
        case ready(PreparedPush)
        case refused(TransportResult)
    }

    private struct PreparedPush: Sendable {
        let connection: APNsEnvironmentConnection
        let url: URL
        let payload: Data
        let apnsID: String
        let collapseID: String?
        let priority: APNsPriority
        let topic: String
        let expiresAt: Date
    }

    private func prepare(_ message: PushMessage) -> Preparation {
        guard let connection = connections[message.environment] else {
            return .refused(Self.refusal("the APNs \(message.environment.rawValue) environment is not configured"))
        }
        guard settings.allowedTopics.contains(message.topic) else {
            return .refused(Self.refusal("the topic is not one of the configured APNs topics"))
        }
        guard let token = APNsDeviceToken(message.deviceToken.revealed), let url = connection.endpoint.url(for: token)
        else {
            // A token that is not hexadecimal bytes can never be delivered to; the registry marks it invalid.
            return .refused(
                .rejected(
                    reason: "the device token is not hexadecimal bytes; nothing was sent", invalidatesRecipient: true,
                    providerTimestamp: nil))
        }
        guard !message.deliveryID.isEmpty else {
            return .refused(Self.refusal("the delivery has no identifier for apns-id"))
        }
        let payload: APNsPayload
        do {
            payload = try APNsPayloadBuilder.payload(for: message.presentation)
        } catch {
            return .refused(Self.refusal(error.description))
        }
        return .ready(
            PreparedPush(
                connection: connection, url: url, payload: payload.json,
                apnsID: APNsIdentifiers.apnsID(forDelivery: message.deliveryID),
                collapseID: message.collapseID.isEmpty ? nil : APNsIdentifiers.collapseID(for: message.collapseID),
                priority: APNsPriority.forAlert(message.presentation), topic: message.topic,
                expiresAt: message.expiresAt))
    }

    /// A refusal before anything was sent that retrying the same push cannot fix.
    private static func refusal(_ reason: String) -> TransportResult {
        .rejected(reason: "\(reason); nothing was sent", invalidatesRecipient: false, providerTimestamp: nil)
    }

    // MARK: - Sending (inside the environment's gate)

    private func send(_ push: PreparedPush) async -> TransportResult {
        if Task.isCancelled { return .notSent(reason: "the push was cancelled before it was sent") }
        let connection = push.connection
        let capabilities = connection.client.capabilities
        guard capabilities.http2Only else {
            return Self.refusal(
                "capability: the HTTP transport for APNs cannot send HTTP/2-only requests (\(capabilities.summary))")
        }
        guard let expiration = APNsRequestHeaders.expiration(for: push.expiresAt, now: clock.now()) else {
            return Self.refusal("the notification's validity window ended before it could be sent")
        }
        let token: APNsProviderToken
        do {
            token = try connection.tokens.token(at: clock.now())
        } catch {
            return .notSent(reason: "\(error); nothing was sent")
        }
        let first = await exchange(push, token: token, expiration: expiration)
        guard case .success(.expiredProviderToken) = first else { return finish(first, token: token) }
        // APNs refused the stale token without accepting the notification, so one retry with a new token cannot
        // duplicate it. The retry happens only while the notification is still valid and the push is not cancelled.
        if Task.isCancelled {
            return .notSent(reason: "the push was cancelled after APNs reported an expired provider token")
        }
        guard APNsRequestHeaders.expiration(for: push.expiresAt, now: clock.now()) != nil else {
            return Self.refusal("the notification's validity window ended before a new provider token could be used")
        }
        let replacement: APNsProviderToken
        do {
            replacement = try connection.tokens.replace(expired: token, at: clock.now())
        } catch {
            return .notSent(reason: "\(error); nothing was sent after APNs reported an expired provider token")
        }
        return finish(await exchange(push, token: replacement, expiration: expiration), token: replacement)
    }

    private func exchange(_ push: PreparedPush, token: APNsProviderToken, expiration: Int64) async
        -> Result<APNsResponseClass, HTTPFailure>
    {
        let headers = APNsRequestHeaders.make(
            providerToken: token, apnsID: push.apnsID, expiration: expiration, priority: push.priority,
            topic: push.topic, collapseID: push.collapseID)
        let request = APNsRequest.make(url: push.url, headers: headers, payload: push.payload)
        do {
            let response = try await push.connection.client.send(request)
            return .success(APNsResponseClassifier.classify(response, requestAPNsID: push.apnsID, now: clock.now()))
        } catch {
            return .failure(error)
        }
    }

    private func finish(_ outcome: Result<APNsResponseClass, HTTPFailure>, token: APNsProviderToken)
        -> TransportResult
    {
        switch outcome {
        case .success(let response):
            APNsResultMapping.result(
                for: response, tokenUpdateAllowedAt: APNsProviderTokenCache.nextUpdateAllowed(after: token),
                now: clock.now())
        case .failure(let failure):
            APNsResultMapping.result(for: failure)
        }
    }
}
