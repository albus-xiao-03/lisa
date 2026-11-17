// Maps a validated configuration file (CFG-01) to host settings: owner settings, sources, model, push policy,
// retention and resource bounds.

import Foundation
import LisaConfig
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaICalendar
import LisaInference
import LisaLocalSources
import LisaMIME
import LisaOwnerData
import LisaPorts
import LisaRuntime
import LisaTime

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
        let sources = configuration.sources.map(Self.source)
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
            maxFeedBytes: bounds.maxFeedBytes)
    }

    static func source(_ source: SourceConfiguration) -> HostSource {
        var mailboxAddress: String?
        var floatingTimeZone: TimeZoneID?
        let access: SourceAccess
        switch source.settings {
        case .localImport(let settings):
            let format: LocalSourceFormat = settings.format == .mail ? .mail : .calendar
            access = .localDirectory(URL(fileURLWithPath: settings.directory), format)
        case .mailbox(let settings):
            mailboxAddress = settings.mailboxAddress
            access = .adapter("IMAP mailbox")
        case .calendarFeed(let settings):
            floatingTimeZone = settings.floatingTimeZone
            if case .file(let path) = settings.location {
                access = .localFile(URL(fileURLWithPath: path), .calendar)
            } else {
                access = .adapter("HTTPS calendar subscription")
            }
        case .newsFeed(let settings):
            if case .file(let path) = settings.location {
                access = .localFile(URL(fileURLWithPath: path), .feed)
            } else {
                access = .adapter("RSS/Atom feed")
            }
        case .xAccount:
            access = .adapter("X API")
        case .discordChannel:
            access = .adapter("Discord")
        }
        return HostSource(
            key: source.key, name: source.name, kind: source.kind, enabled: source.enabled,
            staleAfterSeconds: source.staleAfterSeconds, syncIntervalSeconds: source.syncIntervalMinutes * 60,
            retainImportedOnDisable: source.retainImportedOnDisable, access: access, mailboxAddress: mailboxAddress,
            floatingTimeZone: floatingTimeZone)
    }
}
