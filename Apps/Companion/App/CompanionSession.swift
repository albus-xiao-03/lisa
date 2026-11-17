// The companion's session: it configures the app's shared client environment once per process, builds the screens'
// view models, and runs what the app does at launch, on each return to the foreground, after pairing and after this
// device is removed.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation

/// The one session of the companion's process (UI-02, UI-03, NOTIFY-05, plan §6.5, §6.6).
///
/// - Launch: configuring `LisaClientEnvironment` registers the notification categories and the delegate, and points
///   the transport at the saved host address. APNs registration is requested only on a paired device.
/// - When the app becomes active at launch, and each time it returns from the background: the notification permission
///   is read and reported, receipts are recorded for the notifications still listed, the queued actions are sent, and
///   every screen is read again, so the app shows the current state when it is opened. These are signals, not
///   polling: nothing runs while the app is in the background, and nothing is scheduled.
/// - After pairing, every screen is read again and APNs registration is requested. After the host removed this device
///   or the owner unpaired it, every screen is read again so that none keeps showing the owner's data (plan §6.3).
@MainActor
final class CompanionSession {
    /// The session of this process; its first use configures the client environment.
    static let shared = CompanionSession(environment: LisaClientEnvironment.shared)

    /// The app's shared client environment.
    let environment: LisaClientEnvironment
    /// Where the companion is, in both layouts.
    let navigation: CompanionNavigation
    /// The screens' view models; `nil` when the client services could not be built.
    let models: CompanionModels?
    /// Why Lisa can't start, when `models` is `nil`.
    let launchProblem: String?

    private static let servicesUnavailable = "Lisa could not prepare its services on this device."

    private init(environment: LisaClientEnvironment) {
        self.environment = environment
        navigation = CompanionNavigation()
        let credentials: KeychainCredentialStore
        do {
            credentials = try KeychainCredentialStore.forThisApp()
        } catch {
            models = nil
            launchProblem = "Lisa can't start: \(error)."
            return
        }
        environment.configure(credentials: credentials, requiresPairing: true, usesSavedHostAddress: true)
        let built = CompanionModels(environment: environment, credentials: credentials)
        models = built
        launchProblem = built == nil ? (environment.setupProblem ?? Self.servicesUnavailable) : nil
    }

    // MARK: - Lifecycle

    /// Runs when the app becomes active at launch and each time it returns from the background: reads the pairing, then
    /// reads every screen while it reports the notification permission, records receipts and sends the queued actions.
    func becameActive() async {
        guard let models else { return }
        await models.connection.refresh()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshScreens() }
            group.addTask { await self.syncWithHost() }
        }
    }

    /// Asks the system for the APNs token when this device is paired. The app delegate calls it at every launch, so a
    /// token that changed reaches the host.
    func registerForRemoteNotificationsIfPaired() async {
        guard let models else { return }
        await models.connection.refresh()
        guard models.connection.state.isPaired else { return }
        environment.registerForRemoteNotifications()
    }

    /// After pairing: requests APNs registration, reports the notification permission to the new host and reads every
    /// screen again.
    func didPair() async {
        environment.registerForRemoteNotifications()
        await models?.notificationSettings.reportPermission()
        await refreshScreens()
    }

    /// After the host removed this device or the owner unpaired it: stops reading aloud and reads every screen again,
    /// so that each one stops showing the owner's data.
    func clearScreensAfterRemoval() async {
        models?.speaker.stop()
        await refreshScreens()
    }

    /// After the owner sent, applied again or discarded queued actions: reads every screen again, so that their
    /// waiting and conflict marks match the queue.
    func queueChanged() async {
        await refreshScreens()
    }

    /// Shows the screen of a notification the owner opened, and reads that screen again.
    func open(_ item: LisaPushData) async {
        guard let models, let section = navigation.open(item) else { return }
        switch section {
        case .reminders: await models.reminders.load()
        case .rundown: await models.rundown.load()
        case .brief: await models.brief.load()
        default: break
        }
    }

    /// Reads every screen's data again, the host requests at the same time.
    func refreshScreens() async {
        guard let models else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await models.rundown.refresh() }
            group.addTask { await models.brief.refresh() }
            group.addTask { await models.tasks.refresh() }
            group.addTask { await models.reminders.load() }
            group.addTask { await models.notificationSettings.load() }
            group.addTask { await models.connection.refreshDevice() }
        }
        await models.pendingActions.reload()
        await models.capture.refreshPendingCount()
        await models.connectivity.refreshCachedData()
    }

    // MARK: - Internals

    /// Reports the notification permission and records receipts; on a paired device, also sends the queued actions,
    /// reads the screens again when the host answered any of them, and sends an APNs token the host lacks.
    private func syncWithHost() async {
        guard let models else { return }
        await models.notificationSettings.reportPermission()
        await environment.recordListedNotificationReceipts()
        guard models.connection.state.isPaired else { return }
        let report = await models.pendingActions.flush()
        if !(report.applied.isEmpty && report.conflicts.isEmpty && report.failed.isEmpty) {
            await refreshScreens()
        }
        await environment.pushRegistration?.registerIfNeeded()
    }
}
