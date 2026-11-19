// The screen view for each of the companion's sections, with the view models and session actions it needs.

import SwiftUI

/// The view of `section`, used by the sidebar's detail at regular width and by the Settings tab's stack at compact
/// width.
struct SectionScreen: View {
    let section: CompanionSection
    let session: CompanionSession
    let models: CompanionModels

    var body: some View {
        switch section {
        case .rundown:
            RundownView(model: models.rundown)
        case .brief:
            BriefView(model: models.brief, speaker: models.speaker)
        case .reminders:
            RemindersView(model: models.reminders)
        case .capture:
            CaptureView(model: models.capture)
        case .tasks:
            TasksView(model: models.tasks)
        case .pending:
            PendingActionsView(model: models.pendingActions, onQueueChanged: { await session.queueChanged() })
        case .connectivity:
            ConnectivityView(model: models.connectivity, pendingActions: models.pendingActions)
        case .connection:
            ConnectionView(
                connection: models.connection, hostConnection: models.hostConnection,
                notificationSettings: models.notificationSettings, onPaired: { await session.didPair() })
        case .notifications:
            NotificationSettingsView(model: models.notificationSettings)
        case .diagnostics:
            DiagnosticsView(session: session, models: models)
        }
    }
}
