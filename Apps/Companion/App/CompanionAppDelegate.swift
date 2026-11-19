// The companion's application delegate: at every launch it asks for the APNs token once the device is paired, and it
// passes the system's answer to the shared client environment.

import Foundation
import UIKit

/// Receives the launch and the APNs registration callbacks (NOTIFY-02, plan §6.5, D-48).
///
/// It runs for every launch, in the foreground or in the background, so a changed token reaches the host. It only
/// forwards what the system reports: the app declares no background modes and Lisa sends no silent pushes.
@MainActor
final class CompanionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let session = CompanionSession.shared
        Task { await session.registerForRemoteNotificationsIfPaired() }
        return true
    }

    func application(
        _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await LisaClientEnvironment.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        LisaClientEnvironment.shared.didFailToRegisterForRemoteNotifications(error)
    }
}
