// The window's root: the companion's screens once the session has its view models, otherwise why Lisa can't start;
// and the session's work each time the app becomes active.

import SwiftUI

/// The root of the companion's window. When the scene becomes active at launch, and each time it returns from the
/// background, the session reads the notification permission, sends queued actions and reads the screens again
/// (plan §6.5, §6.6). A brief interruption that leaves the app in the foreground, such as Control Center or a system
/// alert, does not count as a return.
struct CompanionRootView: View {
    let session: CompanionSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var returnsFromBackground = true

    var body: some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    returnsFromBackground = true
                case .active:
                    guard returnsFromBackground else { return }
                    returnsFromBackground = false
                    Task { await session.becameActive() }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let models = session.models {
            CompanionLayout(session: session, models: models, navigation: session.navigation)
        } else {
            ContentUnavailableView(
                "Lisa Can't Start", systemImage: "exclamationmark.triangle",
                description: Text(session.launchProblem ?? "Lisa could not prepare its services on this device."))
        }
    }
}
