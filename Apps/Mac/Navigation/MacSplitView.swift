// The Mac app's window: a sidebar of the screens with the host's mode at its foot, the chosen screen beside it, and the
// session events every screen depends on.

import LisaPresentation
import SwiftUI

/// The sidebar and the chosen screen (UI-01). The sidebar's order matches the Command-number shortcuts of
/// `MacCommands`, and arrow keys move through it.
///
/// It also reacts to the session's events: a notification the owner opened shows its screen, and each action the owner
/// takes rereads the queue, so the waiting and conflict marks stay current.
struct MacSplitView: View {
    let session: MacSession
    let models: MacModels
    @Bindable var navigation: MacNavigation

    var body: some View {
        NavigationSplitView(
            sidebar: {
                List(selection: $navigation.section) {
                    Section("Today") {
                        row(.today)
                        row(.brief)
                    }
                    Section("Review") {
                        row(.inbox)
                            .badge(models.inbox.reviewCount)
                        row(.ideas)
                        row(.memory)
                    }
                    Section("Lisa") {
                        row(.settings)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                .safeAreaInset(edge: .bottom) {
                    Label(session.host.mode.title, systemImage: session.host.mode.systemImage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .accessibilityLabel("Lisa's host: \(session.host.mode.title)")
                }
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    HostModeBanner(session: session, connectivity: models.connectivity)
                }
            }
        )
        .onChange(of: session.environment.itemToOpen, initial: true) { _, item in
            guard item != nil, let opened = session.environment.takeItemToOpen() else { return }
            Task { await session.open(opened) }
        }
        .onChange(of: models.capture.lastOutcome) { reloadQueue() }
        .onChange(of: models.tasks.lastOutcome) { reloadQueue() }
        .onChange(of: models.inbox.lastOutcome) { reloadQueue() }
        .onChange(of: models.memory.lastOutcome) { reloadQueue() }
    }

    private func row(_ section: MacSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.systemImage)
        }
    }

    private func reloadQueue() {
        Task { await models.pendingActions.reload() }
    }
}
