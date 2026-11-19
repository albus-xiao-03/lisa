// The connectivity screen and the app's connectivity hub: host reachable, unreachable, not paired or removed, the last
// successful contact, and the age of cached data.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// Connectivity and cached-data age (UI-02, NOTIFY-07), and the place every model reports its exchanges with the host.
///
/// - `status` follows the latest exchange any model reported, so the app knows the host's state without polling;
///   `check()` asks the host explicitly (`GET /v1/health`), and `checkOnSignals(_:)` checks on an injected trigger.
/// - When the host rejects this device's credential (401), the device was removed: the cached data and delivered
///   notifications are cleared (plan §6.3) and `status` stays `.revoked` until the host answers again after pairing.
@MainActor
@Observable
public final class ConnectivityModel: HostContactReporting {
    /// The connection to the host as last observed.
    public private(set) var status: HostStatus = .unknown
    /// When the host last answered.
    public private(set) var lastSuccessfulContact: Date?
    /// When the host was last tried, whatever the result.
    public private(set) var lastAttempt: Date?
    /// What is cached for outages, with fetch times.
    public private(set) var cachedData: [CachedDataSummary] = []
    /// Whether `check()` is running.
    public private(set) var isChecking = false

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let cleanup: DeviceDataCleanup

    /// - Parameters:
    ///   - context: the client services.
    ///   - notifications: removes delivered notifications when the host removes this device.
    public init(context: ClientContext, notifications: (any DeliveredNotificationRemoving)? = nil) {
        self.context = context
        cleanup = DeviceDataCleanup(cache: context.cache, notifications: notifications)
    }

    /// The cached data of `kind`, if any.
    public func cached(_ kind: CacheKey.Kind) -> CachedDataSummary? {
        cachedData.first { $0.kind == kind }
    }

    /// Asks the host whether it can be reached, when the device is paired, and reads the cache's ages.
    public func check() async {
        isChecking = true
        defer { isChecking = false }
        if context.requiresPairing {
            let installation = try? await context.client.installation()
            guard installation?.isPaired == true else {
                await record(.notPaired)
                await refreshCachedData()
                return
            }
        }
        do throws(ClientError) {
            _ = try await context.client.health()
            await record(.reached)
        } catch {
            if let contact = HostContact(error) { await record(contact) }
        }
        await refreshCachedData()
    }

    /// Checks once for every signal, for example when the app returns to the foreground or the network path changes.
    /// Returns when the signals end or the calling task is cancelled.
    public func checkOnSignals(_ signals: AsyncStream<Void>) async {
        for await _ in signals {
            if Task.isCancelled { break }
            await check()
        }
    }

    /// Reads what the cache holds and when it was fetched.
    public func refreshCachedData() async {
        let cache = context.cache
        var summaries: [CachedDataSummary] = []
        if let brief = try? await cache.latestBrief() {
            summaries.append(CachedDataSummary(kind: .brief, localDate: brief.value.date, fetchedAt: brief.fetchedAt))
        }
        if let rundown = try? await cache.latestRundown() {
            summaries.append(
                CachedDataSummary(kind: .rundown, localDate: rundown.value.date, fetchedAt: rundown.fetchedAt))
        }
        if let tasks = try? await cache.tasks() {
            summaries.append(CachedDataSummary(kind: .tasks, localDate: nil, fetchedAt: tasks.fetchedAt))
        }
        cachedData = summaries
    }

    /// Records one exchange with the host. A removal clears the cached data and delivered notifications first.
    public func record(_ contact: HostContact) async {
        let now = context.now()
        lastAttempt = now
        switch contact {
        case .reached:
            status = .reachable
            lastSuccessfulContact = now
        case .unreachable(let reason):
            if status != .revoked { status = .unreachable(reason: reason) }
        case .incompatible(let version):
            if status != .revoked { status = .incompatible(version: version) }
        case .notPaired:
            if status != .revoked { status = .notPaired }
        case .revoked:
            status = .revoked
            await cleanup.run()
            await refreshCachedData()
        }
    }
}
