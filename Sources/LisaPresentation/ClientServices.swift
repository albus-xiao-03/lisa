// The client side of one app process: one typed client, one offline queue and one response cache over the app's own
// storage, shared by the screens, the notification delegate and the App Intents.

import Foundation
import LisaAPIContract
import LisaClient

/// The client services of an app process (UI-03, NOTIFY-05, SIRI-01).
///
/// The app builds them once at launch. Every screen, the notification delegate and the App Intents, which run in the
/// app's own process, use this one instance, so each file has a single writer: one `OfflineQueue` writes the queue
/// file and one `ResponseCache` the cache directory (`OfflineQueue` does not coordinate with other writers). The
/// storage directory holds:
/// - `queue/queue.json`, the offline queue;
/// - `cache/`, the cached brief, rundown and task lists.
///
/// The files are owner-only (0600, in 0700 directories), and every write applies `protection`, such as
/// `.completeFileProtectionUntilFirstUserAuthentication` on iPhone and iPad, so that actions taken on a locked device
/// can still be queued (plan §6.5).
public struct ClientServices: Sendable {
    /// How long an action tries to reach the host before it stays pending, unless the app chooses another limit.
    public static let defaultSubmitTimeLimit: Duration = .seconds(10)

    /// What the view models and the App Intents use.
    public let context: ClientContext
    /// Handles responses to delivered notifications through the same client and queue.
    public let notificationActions: NotificationActionHandler
    /// The offline queue's file.
    public let queueFile: URL
    /// The response cache's directory.
    public let cacheDirectory: URL

    /// Opens the queue and the cache in `storageDirectory` and builds the client over `transport`.
    ///
    /// - Parameters:
    ///   - transport: carries requests to the host, normally the app's `RetargetableTransport`.
    ///   - credentials: holds this installation's identity and device credential.
    ///   - requiresPairing: `true` for the iPhone, iPad and a Mac in client mode; `false` only for a transport that
    ///     authenticates the owner itself, such as the Mac's embedded host.
    ///   - storageDirectory: a directory used only by this app's client files.
    ///   - protection: data-protection options for every queue and cache write.
    ///   - submitTimeLimit: how long an action may try to reach the host before it stays pending.
    ///   - timeZone: the device's zone.
    ///   - now: the clock recorded in the queue and the cache.
    /// - Throws: when the stored queue cannot be read, such as a file other users can write or an unknown format.
    public init(
        transport: any APITransport, credentials: any CredentialStore, requiresPairing: Bool, storageDirectory: URL,
        protection: Data.WritingOptions = [], submitTimeLimit: Duration = ClientServices.defaultSubmitTimeLimit,
        timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        queueFile = storageDirectory.appendingPathComponent("queue", isDirectory: true)
            .appendingPathComponent("queue.json")
        cacheDirectory = storageDirectory.appendingPathComponent("cache", isDirectory: true)
        let client = LisaAPIClient(transport: transport, credentials: credentials, requiresPairing: requiresPairing)
        let queue = try OfflineQueue(storage: FileQueueStorage(fileURL: queueFile, protection: protection), clock: now)
        let cache = ResponseCache(storage: FileResponseCacheStorage(directory: cacheDirectory, protection: protection))
        context = ClientContext(
            reader: CachedReader(client: client, cache: cache, timeZone: timeZone, clock: now), queue: queue,
            submitTimeLimit: submitTimeLimit, requiresPairing: requiresPairing, timeZone: timeZone, now: now)
        notificationActions = NotificationActionHandler(client: client, queue: queue)
    }

    /// The typed client.
    public var client: LisaAPIClient { context.client }

    /// The offline queue.
    public var queue: OfflineQueue { context.queue }
}
