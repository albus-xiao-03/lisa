// Builds a host's network adapters from its settings and platform: source connectors, the live transports of the
// channels set to live, and the model provider. Building an adapter contacts no service.

import Foundation
import LisaAPNs
import LisaCalendarFeeds
import LisaDelivery
import LisaDiscordSource
import LisaDomain
import LisaHTTP
import LisaIMAP
import LisaInference
import LisaLocalSources
import LisaNewsFeeds
import LisaOpenAICompatible
import LisaPorts
import LisaSMTP
import LisaSecrets
import LisaTime
import LisaTwilio
import LisaXSource

/// The adapters of one host.
struct HostAdapters: Sendable {
    let settings: HostSettings
    let platform: HostPlatform
    /// Shared by the feed, X and Discord connectors and the captured-page retriever.
    private let connectorClient: Result<any HTTPClient, AdapterUnavailable>

    /// Why an adapter cannot be built; the text contains no secret.
    struct AdapterUnavailable: Error, CustomStringConvertible {
        let description: String
    }

    init(settings: HostSettings, platform: HostPlatform) {
        self.settings = settings
        self.platform = platform
        connectorClient = Self.client(.connectors, platform.network)
    }

    static func client(_ purpose: HTTPClientPurpose, _ network: HostNetwork) -> Result<
        any HTTPClient, AdapterUnavailable
    > {
        do {
            return .success(try network.makeHTTPClient(purpose))
        } catch {
            return .failure(AdapterUnavailable(description: "the network library is unavailable: \(error)"))
        }
    }

    /// The connector of a source.
    func connector(for access: SourceAccess) -> Result<any SourceConnector, AdapterUnavailable> {
        let secrets = platform.secrets
        let clock = platform.clock
        switch access {
        case .localDirectory(let url, let format):
            return .success(LocalDirectoryConnector(directory: url, format: format))
        case .localFile(let url, let format):
            return .success(LocalDirectoryConnector(file: url, format: format))
        case .imapMailbox(var mailbox):
            if mailbox.trustStorePath == nil { mailbox.trustStorePath = platform.network.mailTrustStorePath }
            return .success(IMAPMailboxConnector(settings: mailbox, secrets: secrets, clock: clock))
        case .calendarSubscription(let address):
            return connectorClient.map { client in
                CalendarSubscriptionConnector(address: address, secrets: secrets, client: client, clock: clock)
            }
        case .newsFeed(let address):
            return connectorClient.map { client in
                NewsFeedConnector(
                    address: address, secrets: secrets, client: client, clock: clock,
                    options: NewsFeedOptions(maxDocumentBytes: settings.maxFeedBytes))
            }
        case .xAccount(let configuration):
            return connectorClient.map { client in
                XAccountConnector(configuration: configuration, secrets: secrets, http: client, clock: clock)
            }
        case .discordChannel(let configuration):
            return connectorClient.map { client in
                DiscordChannelConnector(configuration: configuration, secrets: secrets, http: client, clock: clock)
            }
        }
    }

    /// The retriever of the pages behind links the owner captures, on the connectors' HTTP client (NEWS-01).
    func capturedPageRetrieval() -> Result<any CapturedPageRetrieval, AdapterUnavailable> {
        let clock = platform.clock
        return connectorClient.map { client in
            OwnerPageRetrievalAdapter(retriever: OwnerPageRetriever(client: client, clock: clock))
        }
    }

    /// The model provider, or a note explaining why items that need a model wait (MODEL-04).
    func modelProvider() -> (provider: (any ModelProvider)?, note: String?) {
        switch settings.model {
        case .none:
            return (nil, nil)
        case .deterministic:
            return (DeterministicProvider(), nil)
        case .openAICompatible(let endpoint, let model, let apiKey):
            guard let url = URL(string: endpoint) else {
                return (nil, "the model endpoint is not a valid address; email waits for a model")
            }
            let http: any HTTPClient
            switch Self.client(.model, platform.network) {
            case .success(let client): http = client
            case .failure(let reason):
                return (nil, "the model adapter is unavailable: \(reason); email waits for a model")
            }
            let clock = platform.clock
            do {
                let provider = try OpenAICompatibleProvider(
                    configuration: OpenAICompatibleConfiguration(
                        endpoint: url, model: model, apiKey: apiKey,
                        requestTimeoutSeconds: settings.modelTimeoutSeconds,
                        limits: settings.modelLimits),
                    secrets: platform.secrets, http: http, now: { clock.now() })
                return (provider, nil)
            } catch {
                return (nil, "the model endpoint cannot be used: \(error); email waits for a model")
            }
        }
    }

    /// The live transports of the channels whose mode is live. A live channel whose adapter is missing or unusable
    /// stops the host from starting, rather than pretending to deliver (D-36).
    func liveTransports() throws(HostError) -> LiveTransports {
        let delivery = settings.ownerSettings.delivery
        let adapters = settings.deliveryAdapters
        let secrets = platform.secrets
        let clock = platform.clock
        var live = LiveTransports(localNotification: platform.localNotifications)
        if delivery.emailMode == .live {
            guard var smtp = adapters.smtp else {
                throw .liveDeliveryUnavailable(channel: "email", reason: "no email adapter is configured")
            }
            if let problem = smtp.problems.first { throw .liveDeliveryUnavailable(channel: "email", reason: problem) }
            if smtp.trustStorePath == nil { smtp.trustStorePath = platform.network.mailTrustStorePath }
            live.email = SMTPEmailTransport(settings: smtp, secrets: secrets, clock: clock)
        }
        if delivery.callMode == .live {
            guard let twilio = adapters.twilio else {
                throw .liveDeliveryUnavailable(channel: "call", reason: "no call adapter is configured")
            }
            if let problem = twilio.problems.first { throw .liveDeliveryUnavailable(channel: "call", reason: problem) }
            switch Self.client(.calls, platform.network) {
            case .success(let http):
                live.call = TwilioCallTransport(settings: twilio, secrets: secrets, http: http, clock: clock)
            case .failure(let reason): throw .liveDeliveryUnavailable(channel: "call", reason: reason.description)
            }
        }
        if delivery.pushMode == .live {
            guard let apns = adapters.apns else {
                throw .liveDeliveryUnavailable(channel: "push", reason: "no APNs adapter is configured")
            }
            switch Self.pushTransport(apns, secrets: secrets, clock: clock, network: platform.network) {
            case .success(let transport): live.push = transport
            case .failure(let reason): throw .liveDeliveryUnavailable(channel: "push", reason: reason.description)
            }
        }
        return live
    }

    /// The APNs transport, with one HTTP client per environment; every environment must support HTTP/2-only
    /// requests in the library actually loaded (NOTIFY-04).
    static func pushTransport(
        _ apns: APNsSettings, secrets: any SecretStore, clock: any WallClock, network: HostNetwork
    ) -> Result<APNsPushTransport, AdapterUnavailable> {
        var clients: [APNsEnvironment: any HTTPClient] = [:]
        for environment in apns.credentials.keys {
            switch client(.apns(environment), network) {
            case .success(let http): clients[environment] = http
            case .failure(let reason): return .failure(reason)
            }
        }
        let transport: APNsPushTransport
        do {
            transport = try APNsPushTransport(settings: apns, secrets: secrets, clock: clock, clients: clients)
        } catch {
            return .failure(AdapterUnavailable(description: error.description))
        }
        if let missing = transport.environmentStatus.first(where: { !$0.http2Only }) {
            return .failure(
                AdapterUnavailable(
                    description: "\(missing.environment.rawValue) needs HTTP/2-only requests, which "
                        + "\(missing.transportSummary) lacks"))
        }
        return .success(transport)
    }
}
