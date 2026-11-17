// The one set of client services an app process shares: its screens, its notification delegate and its App Intents,
// configured once at launch over one transport, one queue and one cache.

import Foundation
import LisaAPIContract
import LisaClient
import LisaPresentation
import Observation
import UserNotifications

/// The app's process-wide client environment (UI-03, NOTIFY-05, SIRI-01).
///
/// The app calls `configure(credentials:requiresPairing:usesSavedHostAddress:)` once, in its `App` initializer, before
/// any scene appears; the system also runs that initializer when it launches the app in the background for a
/// notification action or an App Intent. From then on everything shares one `ClientServices`, so the offline queue and
/// the cache each have a single writer. The App Intents live in the app targets, not in an extension, for exactly this
/// reason. Until it is configured, `intentActions()` is `nil` and the intents answer that Lisa is not set up.
///
/// - Transport: one `RetargetableTransport`. With `usesSavedHostAddress` (the companion), configuring points it at the
///   saved host address at once, so a background launch reaches the host too, and `hostConnection` is the
///   `HostEndpointConfiguring` for `ConnectionModel`. The Mac app points it at its embedded host, or at a running
///   `lisa serve`, with `setHostTransport(_:)`.
/// - Notifications: configuring registers Lisa's categories and installs the notification delegate. On paired
///   devices (`requiresPairing`), the app calls `registerForRemoteNotifications()` at every launch and passes the
///   system's answer to `didRegisterForRemoteNotifications(deviceToken:)` or
///   `didFailToRegisterForRemoteNotifications(_:)`; `pushRegistration` sends the token to the host once paired.
///   Notification permission is read through `SystemNotificationPermissions` and requested only when pairing offers
///   to turn notifications on.
/// - Opening: a notification opened by the owner sets `itemToOpen`; the screen that shows it takes it with
///   `takeItemToOpen()`.
@MainActor
@Observable
final class LisaClientEnvironment {
    /// The environment of this app process.
    static let shared = LisaClientEnvironment()

    /// The client services, once configured.
    private(set) var services: ClientServices?
    /// The saved host address and TLS trust, for the connection screen; set when configured with
    /// `usesSavedHostAddress`.
    private(set) var hostConnection: HostConnectionController?
    /// The app's connectivity hub, which every model and intent reports to.
    private(set) var connectivity: ConnectivityModel?
    /// APNs token registration, on builds that pair as a device.
    private(set) var pushRegistration: PushRegistrationModel?
    /// The item of the notification the owner opened last, until a screen takes it.
    private(set) var itemToOpen: LisaPushData?
    /// Why the client services could not be built, if they could not.
    private(set) var setupProblem: String?

    /// The app's single transport to its host.
    @ObservationIgnored let transport = RetargetableTransport()
    @ObservationIgnored private var notificationDelegate: LisaNotificationDelegate?

    private init() {}

    /// Builds the client services once: the queue and cache in `ProtectedStorageLocation`, the client over `transport`,
    /// the connectivity hub, the notification delegate and, when `requiresPairing`, APNs registration. Later calls
    /// change nothing, so the storage keeps a single writer. Returns whether the services exist.
    ///
    /// - Parameters:
    ///   - credentials: the device identity store, normally `KeychainCredentialStore.forThisApp()`.
    ///   - requiresPairing: `true` for the iPhone, iPad and a Mac in client mode; `false` for the Mac's embedded host,
    ///     whose in-process transport authenticates the owner.
    ///   - usesSavedHostAddress: whether requests go to the address the owner saved on the connection screen, read
    ///     now; `false` when the app sets the transport itself.
    ///   - submitTimeLimit: how long an action, including a notification action in a background launch, tries to
    ///     reach the host before it stays pending.
    @discardableResult
    func configure(
        credentials: any CredentialStore, requiresPairing: Bool, usesSavedHostAddress: Bool,
        submitTimeLimit: Duration = ClientServices.defaultSubmitTimeLimit
    ) -> Bool {
        if services != nil { return true }
        let center = UNUserNotificationCenter.current()
        LisaNotificationCategories.register(on: center)
        do {
            let location = try ProtectedStorageLocation.standard()
            let built = try ClientServices(
                transport: transport, credentials: credentials, requiresPairing: requiresPairing,
                storageDirectory: location.directory, protection: ProtectedStorageLocation.fileProtection,
                submitTimeLimit: submitTimeLimit)
            let hub = ConnectivityModel(context: built.context, notifications: SystemDeliveredNotifications())
            let delegate = LisaNotificationDelegate(
                handler: built.notificationActions, recordsReceipts: requiresPairing, timeLimit: submitTimeLimit
            ) { [weak self] item in
                self?.itemToOpen = item
            }
            center.delegate = delegate
            notificationDelegate = delegate
            if usesSavedHostAddress {
                hostConnection = HostConnectionController(
                    transport: transport, settingsFile: location.connectionSettingsFile,
                    protection: ProtectedStorageLocation.fileProtection
                ) { trust, endpoint in
                    try PinnedServerTrustEvaluator(trust: trust, endpoint: endpoint)
                }
            }
            services = built
            connectivity = hub
            if requiresPairing, let topic = ThisAppBuild.bundleIdentifier {
                pushRegistration = PushRegistrationModel(
                    context: built.context, environment: ThisAppBuild.apnsEnvironment, topic: topic, contacts: hub)
            }
            setupProblem = nil
            return true
        } catch {
            setupProblem = "Lisa could not open its files on this device: \(error)"
            return false
        }
    }

    /// Sends requests to `target`, such as the Mac's embedded host, or refuses them while `nil`.
    func setHostTransport(_ target: (any APITransport)?) {
        transport.retarget(to: target)
    }

    /// The work behind the App Intents, over the shared services; `nil` until configured.
    func intentActions() -> SiriActions? {
        guard let services else { return nil }
        return SiriActions(context: services.context, contacts: connectivity)
    }

    // MARK: - Notifications

    /// Asks the system for the APNs token; call it at every launch of a build that pairs as a device.
    func registerForRemoteNotifications() {
        guard pushRegistration != nil else { return }
        RemoteNotificationRegistration.register()
    }

    /// Passes the token the system returned to the host, from the app delegate.
    func didRegisterForRemoteNotifications(deviceToken: Data) async {
        await pushRegistration?.receive(deviceToken: deviceToken)
    }

    /// Records that the system could not register for remote notifications, from the app delegate.
    func didFailToRegisterForRemoteNotifications(_ error: any Error) {
        pushRegistration?.registrationFailed(reason: error.localizedDescription)
    }

    /// Records receipts for the Lisa notifications still listed in Notification Center. Call it at launch and on each
    /// return to the foreground.
    func recordListedNotificationReceipts() async {
        await notificationDelegate?.recordListedReceipts()
    }

    /// The item of the notification the owner opened, once; `nil` when none is waiting.
    func takeItemToOpen() -> LisaPushData? {
        defer { itemToOpen = nil }
        return itemToOpen
    }
}
