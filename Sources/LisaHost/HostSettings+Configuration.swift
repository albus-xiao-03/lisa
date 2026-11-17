// Maps a validated configuration file (CFG-01) to host settings: owner settings, sources, model, push policy,
// retention and resource bounds.

import Foundation
import LisaAPNs
import LisaCalendarFeeds
import LisaConfig
import LisaCurl
import LisaDelivery
import LisaDevices
import LisaDiscordSource
import LisaDomain
import LisaICalendar
import LisaIMAP
import LisaInference
import LisaLocalSources
import LisaMIME
import LisaNewsFeeds
import LisaOwnerData
import LisaPorts
import LisaRuntime
import LisaSMTP
import LisaTime
import LisaTwilio
import LisaXSource

extension HostSettings {
    /// Host settings for a validated configuration. Network sources whose adapters are not in this build are kept
    /// and reported as unavailable; nothing configured is silently dropped.
    public init(configuration: LisaConfiguration, applicationVersion: String) throws {
        let model: ModelChoice =
            switch configuration.model.provider {
            case .none: .none
            case .deterministic: .deterministic
            case .openAICompatible:
                .openAICompatible(
                    endpoint: configuration.model.endpoint?.absoluteString ?? "",
                    model: configuration.model.modelIdentifier ?? "", apiKey: configuration.model.apiKeySecret)
            }
        let limits = configuration.model.limits
        let apns = configuration.notifications.apns
        let pushPolicy = PushRegistrationPolicy(
            allowedTopics: Set(apns?.topics ?? []),
            allowedEnvironments: Set(
                (apns?.environments ?? []).compactMap { LisaDomain.APNsEnvironment(rawValue: $0.rawValue) }))
        let sources = configuration.sources.map { Self.source($0, applicationVersion: applicationVersion) }
        let mailbox = configuration.sources.lazy.compactMap { source -> String? in
            if case .mailbox(let settings) = source.settings { return settings.mailboxAddress }
            return nil
        }.first
        let bounds = configuration.limits
        let retention = configuration.retention
        self.init(
            dataDirectory: configuration.dataDirectoryURL, applicationVersion: applicationVersion,
            ownerSettings: configuration.ownerSettings(), model: model,
            dataSharing: ModelDataSharing(rawValue: configuration.model.dataSharing.rawValue) ?? .none,
            modelLimits: ModelUsageLimits(
                maxInputCharacters: limits.maxInputCharacters, maxOutputTokens: limits.maxOutputTokens,
                maxRequestsPerDay: limits.maxRequestsPerDay, maxResponseBytes: limits.maxResponseBytes,
                maxItems: limits.maxItems),
            pushPolicy: pushPolicy, sources: sources,
            retention: RetentionSettings(
                rawContentDays: retention.rawContentDays, deliveryHistoryDays: retention.deliveryHistoryDays,
                auditDays: retention.auditDays, feedItemDays: retention.feedItemDays,
                rawContentMaxBytes: bounds.rawContentMaxBytes),
            runtime: RuntimeOptions(
                maxConcurrentSources: bounds.maxConcurrentRequests,
                retention: RetentionSettings(
                    rawContentDays: retention.rawContentDays, deliveryHistoryDays: retention.deliveryHistoryDays,
                    auditDays: retention.auditDays, feedItemDays: retention.feedItemDays,
                    rawContentMaxBytes: bounds.rawContentMaxBytes)),
            syncLimits: SyncLimits(
                maxItems: bounds.maxItemsPerSync, maxBytes: bounds.maxBytesPerSync,
                timeoutSeconds: bounds.syncTimeoutSeconds),
            emailSender: configuration.email.map { EmailSender(address: $0.fromAddress, name: $0.fromName) }
                ?? EmailSender(address: mailbox ?? "lisa@localhost.invalid", name: "Lisa"),
            idempotencyRetentionDays: configuration.api.idempotencyRetentionDays,
            logMaxBytes: UInt64(max(1, bounds.logMaxBytes)), logKeepFiles: bounds.logKeepFiles,
            messageLimits: MIMELimits(maxMessageBytes: bounds.maxMessageBytes),
            calendarLimits: ICalendarLimits(
                maxOccurrencesPerEvent: bounds.maxRecurrenceOccurrencesPerEvent,
                maxTotalOccurrences: bounds.maxTotalOccurrences),
            maxFeedBytes: bounds.maxFeedBytes, deliveryAdapters: Self.deliveryAdapters(configuration),
            modelTimeoutSeconds: configuration.model.requestTimeoutSeconds)
    }

    static func source(_ source: SourceConfiguration, applicationVersion: String) -> HostSource {
        var mailboxAddress: String?
        var floatingTimeZone: TimeZoneID?
        let access: SourceAccess
        switch source.settings {
        case .localImport(let settings):
            let format: LocalSourceFormat = settings.format == .mail ? .mail : .calendar
            access = .localDirectory(URL(fileURLWithPath: settings.directory), format)
        case .mailbox(let settings):
            mailboxAddress = settings.mailboxAddress
            access = .imapMailbox(
                IMAPMailboxSettings(
                    host: settings.host, port: settings.port, security: Self.mailSecurity(settings.security),
                    username: settings.username, password: settings.passwordSecret, folder: settings.folder,
                    addresses: ConfiguredHostScope.addressPolicy(forHost: settings.host)))
        case .calendarFeed(let settings):
            floatingTimeZone = settings.floatingTimeZone
            switch settings.location {
            case .file(let path): access = .localFile(URL(fileURLWithPath: path), .calendar)
            case .url(let url): access = .calendarSubscription(.url(url))
            case .secretURL(let reference): access = .calendarSubscription(.secretURL(reference))
            }
        case .newsFeed(let settings):
            switch settings.location {
            case .file(let path): access = .localFile(URL(fileURLWithPath: path), .feed)
            case .url(let url): access = .newsFeed(.url(url))
            case .secretURL(let reference): access = .newsFeed(.secretURL(reference))
            }
        case .xAccount(let settings):
            access = .xAccount(XAccountConfiguration(userID: settings.userID, bearerToken: settings.bearerTokenSecret))
        case .discordChannel(let settings):
            access = .discordChannel(
                DiscordChannelConfiguration(
                    channelID: settings.channelID, botToken: settings.botTokenSecret,
                    userAgent: DiscordUserAgent(version: applicationVersion)))
        }
        return HostSource(
            key: source.key, name: source.name, kind: source.kind, enabled: source.enabled,
            staleAfterSeconds: source.staleAfterSeconds, syncIntervalSeconds: source.syncIntervalMinutes * 60,
            retainImportedOnDisable: source.retainImportedOnDisable, access: access, mailboxAddress: mailboxAddress,
            floatingTimeZone: floatingTimeZone)
    }

    /// The live delivery adapters the configuration describes. Configuring them sends nothing by itself.
    static func deliveryAdapters(_ configuration: LisaConfiguration) -> DeliveryAdapterSettings {
        let smtp = configuration.email.map { email in
            SMTPSettings(
                host: email.host, port: email.port, security: Self.mailSecurity(email.security),
                username: email.username, passwordSecret: email.passwordSecret,
                addresses: ConfiguredHostScope.addressPolicy(forHost: email.host))
        }
        let twilio = configuration.calls.map { calls in
            TwilioSettings(
                accountSID: calls.accountSID, authTokenSecret: calls.authTokenSecret, fromNumber: calls.fromNumber)
        }
        let apns = configuration.notifications.apns.map { apns in
            APNsSettings(
                teamID: apns.teamID, keyID: apns.keyID, signingKey: apns.signingKeySecret,
                allowedTopics: Set(apns.topics),
                allowedEnvironments: Set(
                    apns.environments.compactMap { LisaDomain.APNsEnvironment(rawValue: $0.rawValue) }))
        }
        return DeliveryAdapterSettings(smtp: smtp, twilio: twilio, apns: apns)
    }

    static func mailSecurity(_ security: TransportSecurity) -> CurlMailSecurity {
        switch security {
        case .implicitTLS: .implicitTLS
        case .startTLS: .startTLS
        }
    }
}
