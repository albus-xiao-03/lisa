// The Mac app's session: it configures the shared client environment once per process, starts the host, builds the
// screens' view models, and runs what the app does at launch, on each return to the app, after the host changes and
// at quit.

import Foundation
import LisaAPIContract
import LisaPresentation

/// The one session of the Mac app's process (UI-01, UI-03, NOTIFY-05, D-48, D-50).
///
/// - Launch: `LisaClientEnvironment` is configured for the owner (`requiresPairing: false`, no saved host address),
///   which registers the notification categories and the delegate; then the host starts (`EmbeddedHostController`).
/// - Whenever the host starts, stops or changes: the configuration's Keychain secrets are listed, this Mac's
///   notification permission is read and recorded on the embedded host, the queued actions are sent and every screen
///   is read again.
/// - Each return to the app: the login item status and the notification permission are read again, and, at most once
///   a minute, the queue is sent and the screens are read again. These are signals, not polling.
/// - Quit: reading aloud stops and the host stops in reverse order of start-up.
@MainActor
final class MacSession {
    /// The session of this process; its first use configures the client environment and starts the host.
    static let shared = MacSession(environment: LisaClientEnvironment.shared)

    /// The app's shared client environment.
    let environment: LisaClientEnvironment
    /// Which screen is shown.
    let navigation: MacNavigation
    /// The app's identity toward its host.
    let credentials: MacOwnerCredentials
    /// The host the screens use.
    let host: EmbeddedHostController
    /// Notifications on this Mac.
    let notifications: MacNotificationsModel
    /// Start at login.
    let loginItem: LoginItemController
    /// The configuration's Keychain secrets.
    let secrets: KeychainSecretsModel
    /// The screens' view models; `nil` when the client services could not be built.
    let models: MacModels?
    /// Why Lisa can't start, when `models` is `nil`.
    let launchProblem: String?

    private var lastRefreshAt: Date?

    private static let servicesUnavailable = "Lisa could not prepare its services on this Mac."
    /// The shortest time between two refreshes caused by returning to the app.
    private static let activationRefreshInterval: TimeInterval = 60

    private init(environment: LisaClientEnvironment) {
        self.environment = environment
        navigation = MacNavigation()
        let credentials = MacOwnerCredentials()
        self.credentials = credentials
        environment.configure(credentials: credentials, requiresPairing: false, usesSavedHostAddress: false)
        let built = MacModels(environment: environment)
        models = built
        launchProblem = built == nil ? (environment.setupProblem ?? Self.servicesUnavailable) : nil
        host = EmbeddedHostController(environment: environment, credentials: credentials)
        notifications = MacNotificationsModel(host: host, credentials: credentials)
        loginItem = LoginItemController()
        secrets = KeychainSecretsModel()
        Task { await self.launch() }
    }

    // MARK: - Lifecycle

    /// Runs when the app becomes active, at launch and on each return to it.
    func becameActive() async {
        loginItem.refresh()
        guard !host.mode.isStarting, !host.isWorking else { return }
        await notifications.refresh()
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < Self.activationRefreshInterval { return }
        await sendQueueAndRefresh()
    }

    /// Tries again to get a host, at the owner's request.
    func retryHost() async {
        await host.retry()
        await hostChanged()
    }

    /// Restarts the host running in the app, at the owner's request.
    func restartHost() async {
        await host.restart()
        await hostChanged()
    }

    /// Shows the screen of a notification the owner opened, and reads that screen again.
    func open(_ item: LisaPushData) async {
        guard let models else { return }
        switch navigation.open(item) {
        case .today:
            await models.rundown.refresh()
            await models.tasks.load(status: .open)
        case .brief:
            await models.brief.load()
        case .inbox:
            await models.inbox.load()
        case .ideas, .memory, .settings:
            break
        }
    }

    /// Stops reading aloud and stops the host, waiting at most `grace` for its current cycle.
    func shutdown(grace: Duration) async {
        models?.speaker.stop()
        await host.stop(grace: grace)
    }

    /// Reads every screen's data again, the host requests at the same time.
    func refreshScreens() async {
        guard let models else { return }
        lastRefreshAt = Date()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await models.rundown.refresh() }
            group.addTask { await models.brief.refresh() }
            group.addTask { await models.tasks.load(status: .open) }
            group.addTask { await models.inbox.load() }
            group.addTask { await models.ideas.refresh() }
            group.addTask { await models.memory.load() }
            group.addTask { await models.settings.refreshHealth() }
            group.addTask { await models.settings.devices.load() }
        }
        await models.pendingActions.reload()
        await models.capture.refreshPendingCount()
        await models.connectivity.refreshCachedData()
    }

    // MARK: - Internals

    private func launch() async {
        loginItem.refresh()
        await host.start()
        await hostChanged()
    }

    /// After the host started, stopped or changed: lists the Keychain secrets, records the notification permission,
    /// sends the queued actions and reads every screen again.
    private func hostChanged() async {
        secrets.load(host.configuration?.configuration)
        if host.mode.isEmbedded { secrets.hostStarted() }
        await notifications.refresh()
        guard !host.mode.isStarting else { return }
        await sendQueueAndRefresh()
    }

    /// Sends the queued actions, then reads every screen again.
    private func sendQueueAndRefresh() async {
        guard let models else { return }
        await models.pendingActions.flush()
        await refreshScreens()
    }
}
