// Asks the system for this device's APNs token at every launch; the app delegate passes the token on.

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Registers for remote notifications (NOTIFY-02, plan §6.5). The system answers through the app delegate's
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` or
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)`, which pass the result to
/// `LisaClientEnvironment`. Registering asks the person nothing and enables no background mode: Lisa sends no silent
/// pushes.
@MainActor
enum RemoteNotificationRegistration {
    /// Asks the system for the current APNs token. Call it at every launch, so a changed token reaches the host.
    static func register() {
        #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
