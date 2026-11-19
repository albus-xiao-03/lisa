// The view models of the companion's screens, built once per process over the app's shared client services.

import LisaClient
import LisaPresentation

/// Every screen's view model (UI-02), with the adapters it needs, over one `ClientServices` (D-48).
///
/// Every model reports its exchanges with the host to the one `ConnectivityModel`, so connectivity is known without
/// polling. Pairing uses the same credential store as the client, and the connection screen's address and trust go
/// through the environment's `HostConnectionController`.
struct CompanionModels {
    let connectivity: ConnectivityModel
    let rundown: RundownModel
    let brief: BriefModel
    let capture: CaptureModel
    let tasks: TasksModel
    let reminders: RemindersModel
    let pendingActions: PendingActionsModel
    let connection: ConnectionModel
    let notificationSettings: NotificationSettingsModel
    let hostConnection: HostConnectionController
    let pushRegistration: PushRegistrationModel?
    let speaker: BriefSpeaker

    /// The models over `environment`'s services, or `nil` while the environment has none (it could not be
    /// configured).
    ///
    /// - Parameter credentials: the store the environment's client was configured with.
    @MainActor
    init?(environment: LisaClientEnvironment, credentials: any CredentialStore) {
        guard let services = environment.services, let connectivity = environment.connectivity,
            let hostConnection = environment.hostConnection, let device = ThisAppBuild.pairingDevice()
        else { return nil }
        let context = services.context
        self.connectivity = connectivity
        rundown = RundownModel(context: context, contacts: connectivity)
        brief = BriefModel(context: context, contacts: connectivity)
        capture = CaptureModel(context: context, contacts: connectivity)
        tasks = TasksModel(context: context, contacts: connectivity)
        reminders = RemindersModel(context: context, contacts: connectivity)
        pendingActions = PendingActionsModel(context: context, contacts: connectivity)
        connection = ConnectionModel(
            context: context, credentials: credentials, device: device, endpoints: hostConnection,
            connectivity: connectivity, notifications: SystemDeliveredNotifications())
        notificationSettings = NotificationSettingsModel(
            context: context, permissions: SystemNotificationPermissions(), contacts: connectivity)
        self.hostConnection = hostConnection
        pushRegistration = environment.pushRegistration
        speaker = BriefSpeaker()
    }
}
