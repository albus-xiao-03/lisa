// What the composition root needs: validated settings from configuration and services supplied by the platform.

import Foundation
import LisaCalendarFeeds
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
import LisaSecrets
import LisaTime
import LisaXSource

/// How a configured source is reached.
public enum SourceAccess: Hashable, Sendable {
    /// A local directory of files.
    case localDirectory(URL, LocalSourceFormat)
    /// One local file, such as a configured `.ics` calendar.
    case localFile(URL, LocalSourceFormat)
    /// Lisa's own mailbox over IMAP, read only (MAIL-01).
    case imapMailbox(IMAPMailboxSettings)
    /// An HTTPS iCalendar subscription (CAL-01).
    case calendarSubscription(CalendarSubscriptionAddress)
    /// An RSS or Atom feed (NEWS-01).
    case newsFeed(NewsFeedAddress)
    /// A selected X account (NEWS-02).
    case xAccount(XAccountConfiguration)
    /// A Discord channel read by a bot (NEWS-03).
    case discordChannel(DiscordChannelConfiguration)

    /// A short name of the adapter, for health and `lisa doctor`.
    public var adapterName: String {
        switch self {
        case .localDirectory, .localFile: "local files"
        case .imapMailbox: "IMAP mailbox"
        case .calendarSubscription: "HTTPS calendar subscription"
        case .newsFeed: "RSS/Atom feed"
        case .xAccount: "X API"
        case .discordChannel: "Discord"
        }
    }
}

/// One configured source.
public struct HostSource: Hashable, Sendable {
    public var key: String
    public var name: String
    public var kind: SourceKind
    public var enabled: Bool
    public var staleAfterSeconds: Int
    public var syncIntervalSeconds: Int
    public var retainImportedOnDisable: Bool
    public var access: SourceAccess
    /// Lisa's own mailbox address, for mail sources.
    public var mailboxAddress: String?
    /// The zone floating times and dates of a calendar source are read in (CAL-01); `nil` means the owner's zone.
    public var floatingTimeZone: TimeZoneID?

    public init(
        key: String, name: String, kind: SourceKind, enabled: Bool = true, staleAfterSeconds: Int = 6 * 3600,
        syncIntervalSeconds: Int = 900, retainImportedOnDisable: Bool = true, access: SourceAccess,
        mailboxAddress: String? = nil, floatingTimeZone: TimeZoneID? = nil
    ) {
        self.key = key
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.staleAfterSeconds = staleAfterSeconds
        self.syncIntervalSeconds = syncIntervalSeconds
        self.retainImportedOnDisable = retainImportedOnDisable
        self.access = access
        self.mailboxAddress = mailboxAddress
        self.floatingTimeZone = floatingTimeZone
    }
}

/// Which model provider extraction uses.
public enum ModelChoice: Hashable, Sendable {
    /// No model: items needing interpretation wait (MODEL-04).
    case none
    /// The labeled rule-based provider (demo and tests).
    case deterministic
    /// An OpenAI-compatible Chat Completions endpoint.
    case openAICompatible(endpoint: String, model: String, apiKey: SecretReference?)
}

/// Validated settings for one host.
public struct HostSettings: Sendable {
    public var dataDirectory: URL
    public var applicationVersion: String
    /// The configuration's owner settings; stored preferences are overlaid on them.
    public var ownerSettings: OwnerSettings
    public var model: ModelChoice
    public var dataSharing: ModelDataSharing
    public var modelLimits: ModelUsageLimits
    public var pushPolicy: PushRegistrationPolicy
    public var sources: [HostSource]
    public var retention: RetentionSettings
    public var runtime: RuntimeOptions
    public var syncLimits: SyncLimits
    public var emailSender: EmailSender
    public var idempotencyRetentionDays: Int
    public var requestsPerMinute: Int
    public var logMaxBytes: UInt64
    public var logKeepFiles: Int
    /// Dry-run captures kept for inspection.
    public var dryRunCaptureLimit: Int
    /// Per-message bounds (OPS-02).
    public var messageLimits: MIMELimits
    /// Per-calendar bounds, including recurrence expansion (OPS-02).
    public var calendarLimits: ICalendarLimits
    /// The largest feed document read (OPS-02).
    public var maxFeedBytes: Int
    /// The live email, call and push adapters, used only for channels whose mode is live.
    public var deliveryAdapters: DeliveryAdapterSettings
    /// The longest a model request may take.
    public var modelTimeoutSeconds: Int

    public init(
        dataDirectory: URL, applicationVersion: String, ownerSettings: OwnerSettings,
        model: ModelChoice = .deterministic,
        dataSharing: ModelDataSharing = .localOnly, modelLimits: ModelUsageLimits = ModelUsageLimits(),
        pushPolicy: PushRegistrationPolicy = PushRegistrationPolicy(allowedTopics: [], allowedEnvironments: []),
        sources: [HostSource] = [], retention: RetentionSettings = RetentionSettings(),
        runtime: RuntimeOptions = RuntimeOptions(), syncLimits: SyncLimits = SyncLimits(),
        emailSender: EmailSender = EmailSender(address: "lisa@localhost.invalid", name: "Lisa"),
        idempotencyRetentionDays: Int = 30, requestsPerMinute: Int = 300, logMaxBytes: UInt64 = 5_000_000,
        logKeepFiles: Int = 3, dryRunCaptureLimit: Int = 2_000, messageLimits: MIMELimits = MIMELimits(),
        calendarLimits: ICalendarLimits = ICalendarLimits(), maxFeedBytes: Int = 10_000_000,
        deliveryAdapters: DeliveryAdapterSettings = DeliveryAdapterSettings(), modelTimeoutSeconds: Int = 60
    ) {
        self.dataDirectory = dataDirectory
        self.applicationVersion = applicationVersion
        self.ownerSettings = ownerSettings
        self.model = model
        self.dataSharing = dataSharing
        self.modelLimits = modelLimits
        self.pushPolicy = pushPolicy
        self.sources = sources
        self.retention = retention
        self.runtime = runtime
        self.syncLimits = syncLimits
        self.emailSender = emailSender
        self.idempotencyRetentionDays = idempotencyRetentionDays
        self.requestsPerMinute = requestsPerMinute
        self.logMaxBytes = logMaxBytes
        self.logKeepFiles = logKeepFiles
        self.dryRunCaptureLimit = dryRunCaptureLimit
        self.messageLimits = messageLimits
        self.calendarLimits = calendarLimits
        self.maxFeedBytes = maxFeedBytes
        self.deliveryAdapters = deliveryAdapters
        self.modelTimeoutSeconds = modelTimeoutSeconds
    }
}

/// Services the caller's platform supplies.
public struct HostPlatform: Sendable {
    public var clock: any WallClock
    public var secrets: any SecretStore
    /// The Mac app's local-notification transport; `nil` elsewhere.
    public var localNotifications: (any LocalNotificationTransport)?
    public var logToStandardError: Bool
    /// Who opened the host, recorded in the lock file (`serve`, `cli`, `demo`, `mac-app`).
    public var mode: String
    /// How adapters reach the network: libcurl with the system trust store, unless a harness substitutes it.
    public var network: HostNetwork

    public init(
        clock: any WallClock = SystemWallClock(), secrets: any SecretStore,
        localNotifications: (any LocalNotificationTransport)? = nil,
        logToStandardError: Bool = false, mode: String, network: HostNetwork = .libcurl(userAgent: "Lisa")
    ) {
        self.clock = clock
        self.secrets = secrets
        self.localNotifications = localNotifications
        self.logToStandardError = logToStandardError
        self.mode = mode
        self.network = network
    }
}
