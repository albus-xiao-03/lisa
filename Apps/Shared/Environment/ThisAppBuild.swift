// What this build of the app is: its bundle identifier (the APNs topic), its APNs environment, and how this device
// presents itself when it pairs.

import Foundation
import LisaAPIContract
import LisaPresentation

#if os(iOS)
    import UIKit
#endif

/// This build of the app and the device it runs on (plan §6.3, §6.9).
enum ThisAppBuild {
    /// The app has no bundle identifier, so its Keychain items and files cannot be named.
    struct MissingBundleIdentifier: Error, CustomStringConvertible {
        var description: String { "the app has no bundle identifier, so its Keychain items and files cannot be named" }
    }

    /// The app's bundle identifier, which is also its APNs topic.
    static var bundleIdentifier: String? {
        guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else { return nil }
        return identifier
    }

    /// The app's bundle identifier, which names its Keychain items and its client directory.
    static func requiredBundleIdentifier() throws -> String {
        guard let bundleIdentifier else { throw MissingBundleIdentifier() }
        return bundleIdentifier
    }

    /// The APNs environment of this build: `development` for Debug, `production` for Release. It matches the
    /// `aps-environment` (iOS) and `com.apple.developer.aps-environment` (macOS) entitlements that
    /// `Apps/project.yml` assigns per configuration, and relies on the Debug configuration defining `DEBUG` in
    /// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
    static var apnsEnvironment: APNsEnvironmentValue {
        #if DEBUG
            return .development
        #else
            return .production
        #endif
    }

    /// What this device presents when it pairs, or `nil` when the app has no bundle identifier. On iPhone and iPad the
    /// name is the one the system offers apps, which without an extra entitlement is the device model, such as "iPad".
    @MainActor
    static func pairingDevice() -> PairingDevice? {
        guard let bundleIdentifier else { return nil }
        #if os(iOS)
            let device = UIDevice.current
            let deviceClass: DeviceClassValue = device.userInterfaceIdiom == .pad ? .iPad : .iPhone
            return PairingDevice(
                name: device.name, deviceClass: deviceClass, appBundleID: bundleIdentifier,
                environment: apnsEnvironment)
        #else
            return PairingDevice(
                name: Host.current().localizedName ?? "Mac", deviceClass: .mac, appBundleID: bundleIdentifier,
                environment: apnsEnvironment)
        #endif
    }
}
