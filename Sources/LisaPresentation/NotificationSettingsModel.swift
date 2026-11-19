// This device's notification settings: its preferences on the host (including "show titles"), the system permission,
// and reporting the permission to the host at launch and on return to the foreground.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// This device's notification settings (UI-02, NOTIFY-05, NOTIFY-06).
///
/// - Preferences live on the host (`GET`/`PATCH /v1/devices/current/notification-preferences`): enabled, categories,
///   the per-device "show titles" setting, and Time Sensitive. A change expects the revision shown and goes through
///   the durable queue, so it is kept offline; changes made offline that the host cannot have applied yet are merged
///   into one, and a newer state on the host is a recoverable conflict, never overwritten silently.
/// - The system permission comes from an injected `NotificationPermissionReading`. Call `reportPermission()` at launch
///   and on each return to the foreground: it reads the permission and reports it to the host
///   (`PUT /v1/devices/current/notification-status`), so the host stops pushing while notifications are denied and
///   shows why. A report that could not be sent is retried by `reportPermissionIfNeeded()`, for example on reconnect.
@MainActor
@Observable
public final class NotificationSettingsModel {
    /// This device's preferences as the host last answered.
    public private(set) var preferences: LoadState<DeviceNotificationPreferencesDTO> = .idle
    /// Preference changes waiting in the offline queue, merged in order.
    public private(set) var pendingChange: DeviceNotificationPreferencesPatch?
    /// A preference change the host refused because the preferences changed meanwhile.
    public private(set) var conflict: ActionConflict?
    /// Whether a preference change is being submitted.
    public private(set) var isUpdating = false
    /// The outcome of the latest preference change.
    public private(set) var lastOutcome: ActionOutcome?
    /// The system permission as last read.
    public private(set) var permission: NotificationPermissionStatus?
    /// This device as the host showed it after the last permission report, including whether it can receive
    /// notifications.
    public private(set) var registration: DeviceDTO?
    /// When the permission was last reported to the host.
    public private(set) var lastReportedAt: Date?
    /// The outcome of the latest permission report.
    public private(set) var lastReport: ActionOutcome?
    /// Whether the host may not know the current permission because the last report failed.
    public private(set) var reportPending = false

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let permissions: any NotificationPermissionReading
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - context: the client services.
    ///   - permissions: reads and requests the system permission.
    ///   - contacts: where connectivity is reported.
    public init(
        context: ClientContext, permissions: any NotificationPermissionReading,
        contacts: (any HostContactReporting)? = nil
    ) {
        self.context = context
        self.permissions = permissions
        self.contacts = contacts
    }

    /// The preferences shown, with the queued changes applied; `pendingChange` tells which are not confirmed yet.
    public var displayed: DeviceNotificationPreferencesDTO? {
        guard var shown = preferences.value else { return nil }
        if let change = pendingChange {
            if let enabled = change.enabled { shown.enabled = enabled }
            if let categories = change.categories { shown.categories = categories }
            if let showTitles = change.showTitles { shown.showTitles = showTitles }
            if let allow = change.allowTimeSensitive { shown.allowTimeSensitive = allow }
        }
        return shown
    }

    /// Whether `category` is on in the preferences shown.
    public func isEnabled(_ category: NotificationCategoryID) -> Bool {
        displayed?.categories.contains(NotificationCategoryNames.name(of: category)) ?? false
    }

    // MARK: - Preferences

    /// Reads the preferences and the queued changes. A load started later wins over an earlier one.
    public func load() async {
        generation += 1
        let current = generation
        let previous = preferences.result
        preferences = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<DeviceNotificationPreferencesDTO> in
            ReadResult(value: try await client.notificationPreferences(), fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        preferences = next
        await syncQueue()
    }

    /// Turns this device's notifications on or off.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> ActionOutcome {
        await change { patch, _ in patch.enabled = enabled }
    }

    /// Turns the per-device "show titles" setting on or off: a truncated item title in notifications (NOTIFY-06).
    @discardableResult
    public func setShowTitles(_ showTitles: Bool) async -> ActionOutcome {
        await change { patch, _ in patch.showTitles = showTitles }
    }

    /// Allows or disallows Time Sensitive notifications for urgent confirmed deadlines on this device.
    @discardableResult
    public func setAllowTimeSensitive(_ allow: Bool) async -> ActionOutcome {
        await change { patch, _ in patch.allowTimeSensitive = allow }
    }

    /// Turns one category on or off.
    @discardableResult
    public func setCategory(_ category: NotificationCategoryID, enabled: Bool) async -> ActionOutcome {
        await change { patch, shown in
            let name = NotificationCategoryNames.name(of: category)
            var names = Set(shown.categories)
            if enabled { names.insert(name) } else { names.remove(name) }
            let known = NotificationCategoryID.allCases.map(NotificationCategoryNames.name(of:))
            patch.categories = known.filter(names.contains) + names.subtracting(known).sorted()
        }
    }

    /// Applies the refused change again to the preferences now shown, after the owner has seen them.
    @discardableResult
    public func applyAgain() async -> ActionOutcome {
        guard let conflict, let entryID = conflict.entryID else {
            return .failed(reason: "there is no refused change")
        }
        guard let revision = preferences.value?.revision ?? conflict.currentRevision else {
            return .failed(reason: "the current settings are unknown; reload them and try again")
        }
        isUpdating = true
        defer { isUpdating = false }
        return await finish(await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
    }

    /// Discards the refused change; the preferences stay as the host has them. Returns whether it was discarded.
    @discardableResult
    public func discardConflict() async -> Bool {
        guard let entryID = conflict?.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Permission

    /// Reads the system permission and reports it to the host. Call it at launch and on each return to the
    /// foreground (plan §6.5). It is not queued: a report that fails is retried by `reportPermissionIfNeeded()`.
    @discardableResult
    public func reportPermission() async -> ActionOutcome {
        let status = await permissions.currentStatus()
        permission = status
        return await report(status)
    }

    /// Reports the permission once for every signal, such as the app's launch and each return to the foreground.
    /// Returns when the signals end or the calling task is cancelled.
    public func reportOnSignals(_ signals: AsyncStream<Void>) async {
        for await _ in signals {
            if Task.isCancelled { break }
            await reportPermission()
        }
    }

    /// Reports the permission again when the last report failed, for example after reconnecting; `nil` when the host
    /// already knows it.
    @discardableResult
    public func reportPermissionIfNeeded() async -> ActionOutcome? {
        guard reportPending else { return nil }
        return await reportPermission()
    }

    /// Asks the person to allow notifications, then reports the result. Lisa asks only when pairing offers to turn
    /// notifications on (plan §6.5).
    @discardableResult
    public func requestAuthorization() async -> ActionOutcome {
        let status: NotificationPermissionStatus
        do {
            status = try await permissions.requestAuthorization()
        } catch {
            let outcome = ActionOutcome.failed(reason: "the system could not ask for notification permission")
            lastReport = outcome
            return outcome
        }
        permission = status
        return await report(status)
    }

    // MARK: - Internals

    private func change(
        _ apply: (inout DeviceNotificationPreferencesPatch, DeviceNotificationPreferencesDTO) -> Void
    ) async -> ActionOutcome {
        guard let current = preferences.value, let shown = displayed else {
            let outcome = ActionOutcome.failed(reason: "load the notification settings first")
            lastOutcome = outcome
            return outcome
        }
        var patch = DeviceNotificationPreferencesPatch(expectedRevision: current.revision)
        apply(&patch, shown)
        isUpdating = true
        defer { isUpdating = false }
        return await finish(
            await ActionSubmitter(context: context).submit(.updateNotificationPreferences(patch), coalescing: true))
    }

    private func finish(_ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked {
            // The host removed this device: stop showing its preferences.
            generation += 1
            preferences = .failed(.revoked, previous: nil)
        }
        if let updated = submission.decoded(DeviceNotificationPreferencesDTO.self) {
            generation += 1
            preferences = .loaded(ReadResult(value: updated, fetchedAt: context.now(), source: .host))
        }
        await syncQueue()
        if case .conflict = submission.outcome { await load() }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    private func report(_ status: NotificationPermissionStatus) async -> ActionOutcome {
        if context.requiresPairing, (try? await context.client.installation())?.isPaired != true {
            reportPending = false
            let outcome = ActionOutcome.unavailable(reason: ActionOutcome.notPairedReason)
            lastReport = outcome
            return outcome
        }
        let outcome: ActionOutcome
        do throws(ClientError) {
            registration = try await context.client.reportNotificationStatus(status.request)
            lastReportedAt = context.now()
            reportPending = false
            await contacts?.record(.reached)
            outcome = .done
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            reportPending = !LoadFailure(error).hidesData
            if LoadFailure(error).hidesData { registration = nil }
            outcome = ActionOutcome(unqueuedFailure: error)
        }
        lastReport = outcome
        return outcome
    }

    /// Reads the preference changes waiting in the queue, merged in order, and the one the host refused.
    private func syncQueue() async {
        let queue = context.queue
        var merged: DeviceNotificationPreferencesPatch?
        for entry in await queue.pendingEntries where entry.kind == .notificationPreferenceChange {
            guard case .updateNotificationPreferences(let patch)? = try? entry.mutation() else { continue }
            guard var combined = merged else {
                merged = patch
                continue
            }
            if let enabled = patch.enabled { combined.enabled = enabled }
            if let categories = patch.categories { combined.categories = categories }
            if let showTitles = patch.showTitles { combined.showTitles = showTitles }
            if let allow = patch.allowTimeSensitive { combined.allowTimeSensitive = allow }
            merged = combined
        }
        pendingChange = merged
        conflict = await queue.conflictEntries.last { $0.kind == .notificationPreferenceChange }
            .flatMap(ActionConflict.init(entry:))
    }
}
