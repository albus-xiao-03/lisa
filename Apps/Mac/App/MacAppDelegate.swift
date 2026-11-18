// The Mac app's delegate: each return to the app reads the notification permission and refreshes the screens, and
// quitting waits until the host has stopped in the order `lisa serve` uses.

import AppKit
import Foundation

/// Receives the application's activation and termination (UI-01, ARCH-03).
///
/// Quitting asks the session to stop the host: the network server, the owner endpoint file, the processing loop, then
/// the data-directory lock. The app quits once that is done, or after a grace period if the current cycle has not
/// finished; the system then releases the lock with the process, so a second writer can never start early. The app
/// registers for no remote notifications: it does not pair as a device (see `MacNotificationsModel.clientModeNote`).
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// How long quitting waits for the current processing cycle.
    static let quitGrace: Duration = .seconds(20)

    private var isQuitting = false

    func applicationDidBecomeActive(_ notification: Notification) {
        let session = MacSession.shared
        Task { await session.becameActive() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting else { return .terminateLater }
        isQuitting = true
        let session = MacSession.shared
        Task {
            await session.shutdown(grace: MacAppDelegate.quitGrace)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
