// The Lisa companion for iPhone and iPad (UI-02): one window whose layout follows its width, over the app's shared
// client environment, with commands for a hardware keyboard.

import SwiftUI

/// The companion app.
///
/// Its initializer makes the first use of `CompanionSession.shared`, which configures `LisaClientEnvironment` once,
/// before any scene appears (D-48). The system runs the same initializer when it launches the app in the background
/// for a notification action or an App Intent, so those share the one queue and cache too. The app declares no
/// background modes and schedules no local notifications: the host is the only scheduler (plan §6.6).
@main
struct LisaCompanionApp: App {
    @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    private let session: CompanionSession

    init() {
        session = CompanionSession.shared
    }

    var body: some Scene {
        WindowGroup {
            CompanionRootView(session: session)
        }
        .commands {
            CompanionCommands(navigation: session.navigation)
        }
    }
}
