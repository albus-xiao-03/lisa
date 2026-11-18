// The window's root: the Mac app's screens once the session has its view models, otherwise why Lisa can't start.

import SwiftUI

/// The root of the Mac app's window. It puts the host controller and the navigation in the environment, so every
/// screen can offer to reconnect and move between screens.
struct MacRootView: View {
    let session: MacSession

    var body: some View {
        content
            .environment(session.host)
            .environment(session.navigation)
            .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private var content: some View {
        if let models = session.models {
            MacSplitView(session: session, models: models, navigation: session.navigation)
        } else {
            ContentUnavailableView(
                "Lisa Can't Start", systemImage: "exclamationmark.triangle",
                description: Text(session.launchProblem ?? "Lisa could not prepare its services on this Mac."))
        }
    }
}
