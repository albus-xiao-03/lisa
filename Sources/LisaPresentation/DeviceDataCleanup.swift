// What a device removed by the host, or unpaired by the owner, clears: cached data and delivered notifications.

import Foundation
import LisaClient

/// Clears what a removed device must stop showing (plan §6.3): the cached brief, rundown and tasks, and the
/// notifications already delivered to it. Queued actions are the owner's own unsent input and are kept unless the
/// owner discards them.
struct DeviceDataCleanup: Sendable {
    let cache: ResponseCache
    let notifications: (any DeliveredNotificationRemoving)?

    /// Clears the cache and the delivered notifications. Returns `false` when the cache could not be cleared.
    @discardableResult
    func run() async -> Bool {
        var cleared = true
        do {
            try await cache.clear()
        } catch {
            cleared = false
        }
        await notifications?.removeAllDeliveredNotifications()
        return cleared
    }
}
