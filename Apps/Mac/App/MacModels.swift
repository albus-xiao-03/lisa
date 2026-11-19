// The view models of the Mac app's screens, built once per process over the app's shared client services.

import LisaClient
import LisaPresentation

/// Every screen's view model (UI-01), over one `ClientServices` (D-47, D-48).
///
/// Every model reports its exchanges with the host to the one `ConnectivityModel`. The memory screen and the delivery
/// preferences of the settings screen share one `MemoryModel`, so a change made on either shows on both.
struct MacModels {
    let connectivity: ConnectivityModel
    let rundown: RundownModel
    let brief: BriefModel
    let tasks: TasksModel
    let capture: CaptureModel
    let inbox: InboxModel
    let ideas: IdeasModel
    let memory: MemoryModel
    let settings: SettingsHealthModel
    let pendingActions: PendingActionsModel
    let speaker: BriefSpeaker

    /// The models over `environment`'s services, or `nil` while the environment has none (it could not be configured).
    @MainActor
    init?(environment: LisaClientEnvironment) {
        guard let services = environment.services, let connectivity = environment.connectivity else { return nil }
        let context = services.context
        self.connectivity = connectivity
        rundown = RundownModel(context: context, contacts: connectivity)
        brief = BriefModel(context: context, contacts: connectivity)
        tasks = TasksModel(context: context, contacts: connectivity)
        capture = CaptureModel(context: context, contacts: connectivity)
        inbox = InboxModel(context: context, contacts: connectivity)
        ideas = IdeasModel(context: context, contacts: connectivity)
        let preferences = MemoryModel(context: context, contacts: connectivity)
        memory = preferences
        settings = SettingsHealthModel(context: context, contacts: connectivity, preferences: preferences)
        pendingActions = PendingActionsModel(context: context, contacts: connectivity)
        speaker = BriefSpeaker()
    }
}
