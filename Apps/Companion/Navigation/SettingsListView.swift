// The Settings tab at compact width: the pending actions, connectivity, connection, notification settings and
// diagnostics screens.

import LisaPresentation
import SwiftUI

/// The root of the Settings tab. Its rows push the screens on the tab's stack.
struct SettingsListView: View {
    let pendingActions: PendingActionsModel

    var body: some View {
        List {
            Section("Sync") {
                link(.pending)
                    .badge(pendingActions.pendingCount + pendingActions.attentionCount)
                link(.connectivity)
            }
            Section("This Device") {
                link(.connection)
                link(.notifications)
            }
            Section {
                link(.diagnostics)
            }
        }
        .navigationTitle("Settings")
    }

    private func link(_ section: CompanionSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.systemImage)
        }
    }
}
