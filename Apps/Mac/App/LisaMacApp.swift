// Lisa for Mac (UI-01): one window over the app's shared client environment, the host running in the app or the
// `lisa serve` it connects to, and menu commands for every screen.

import SwiftUI

/// The Mac app.
///
/// Its initializer makes the first use of `MacSession.shared`, which configures `LisaClientEnvironment` once, before
/// any scene appears (D-48), and starts the host. The system runs the same initializer when it launches the app for a
/// notification action or an App Intent, so those share the one queue, cache and host too. Closing the window leaves
/// the app, and so the host, running; quitting stops the host in the order `lisa serve` uses (`MacAppDelegate`).
@main
struct LisaMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    private let session: MacSession

    init() {
        session = MacSession.shared
    }

    var body: some Scene {
        WindowGroup("Lisa") {
            MacRootView(session: session)
        }
        .defaultSize(width: 1_040, height: 720)
        .commands {
            MacCommands(session: session)
        }
    }
}
