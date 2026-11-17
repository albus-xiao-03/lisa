// What every view model uses to reach the host: the typed client, the response cache, the offline queue and the clock.

import Foundation
import LisaClient

/// The client-side services the view models share. One context serves every model of an app session; the app builds
/// it for the configured host and the device's credential store.
public struct ClientContext: Sendable {
    /// Reads the brief, the rundown and the task list from the host, or from the cache while the host is unreachable.
    public let reader: CachedReader
    /// The durable queue every mutation is written to before it is sent (UI-03, NOTIFY-05).
    public let queue: OfflineQueue
    /// How long an action tries to reach the host before it is left pending in the queue.
    public let submitTimeLimit: Duration
    /// Whether the client must be paired before it sends anything but pairing. `true` for the iPhone, iPad and a Mac
    /// in client mode; `false` only for a transport that authenticates the owner itself.
    public let requiresPairing: Bool
    /// The zone of the device's current date, which tells whether a cached brief or rundown is from an earlier day.
    public let timeZone: TimeZone
    /// The current time, as the reader records fetch times.
    public let now: @Sendable () -> Date

    /// - Parameters:
    ///   - reader: the cached reader; its client and cache are the ones every model uses.
    ///   - queue: the offline queue shared with the notification-action handler.
    ///   - submitTimeLimit: how long an action may try to reach the host before it stays pending.
    ///   - requiresPairing: whether actions need a paired device.
    ///   - timeZone: the device's zone, as given to the reader.
    ///   - now: the clock given to the reader.
    public init(
        reader: CachedReader, queue: OfflineQueue, submitTimeLimit: Duration = .seconds(10),
        requiresPairing: Bool = true, timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.queue = queue
        self.submitTimeLimit = submitTimeLimit
        self.requiresPairing = requiresPairing
        self.timeZone = timeZone
        self.now = now
    }

    /// The typed client that talks to the host.
    public var client: LisaAPIClient { reader.client }

    /// The cache that keeps the latest brief, rundown and task list.
    public var cache: ResponseCache { reader.cache }
}
