// The regular-width layout (iPad): a sidebar of the companion's screens, and the chosen screen in its own stack.

import LisaPresentation
import SwiftUI

/// Sidebar and detail at regular width (plan §6.5). Choosing another screen starts its stack afresh. The sidebar's
/// order matches the Command-number shortcuts of `CompanionCommands`.
struct CompanionSplitView: View {
    let session: CompanionSession
    let models: CompanionModels
    @Bindable var navigation: CompanionNavigation

    var body: some View {
        NavigationSplitView(
            sidebar: {
                List(selection: $navigation.section) {
                    Section("Today") {
                        row(.rundown)
                        row(.brief)
                        row(.reminders)
                    }
                    Section("Capture and Tasks") {
                        row(.capture)
                        row(.tasks)
                    }
                    Section("Sync") {
                        row(.pending)
                            .badge(models.pendingActions.pendingCount + models.pendingActions.attentionCount)
                        row(.connectivity)
                    }
                    Section("This Device") {
                        row(.connection)
                        row(.notifications)
                        row(.diagnostics)
                    }
                }
                .navigationTitle("Lisa")
            },
            detail: {
                NavigationStack {
                    if let section = navigation.section {
                        SectionScreen(section: section, session: session, models: models)
                    } else {
                        ContentUnavailableView("Choose a Screen", systemImage: "sidebar.left")
                    }
                }
                .id(navigation.section)
            })
    }

    private func row(_ section: CompanionSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.systemImage)
        }
    }
}
