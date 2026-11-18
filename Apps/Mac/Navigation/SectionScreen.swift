// The screen view for each of the Mac app's sections, with the view models and session parts it needs.

import SwiftUI

/// The detail view of one section.
struct SectionScreen: View {
    let section: MacSection
    let session: MacSession
    let models: MacModels

    var body: some View {
        switch section {
        case .today:
            TodayView(models: models, navigation: session.navigation)
        case .brief:
            BriefView(model: models.brief, speaker: models.speaker)
        case .inbox:
            InboxView(model: models.inbox)
        case .ideas:
            IdeasView(model: models.ideas)
        case .memory:
            MemoryView(model: models.memory)
        case .settings:
            SettingsHealthView(session: session, models: models)
        }
    }
}
