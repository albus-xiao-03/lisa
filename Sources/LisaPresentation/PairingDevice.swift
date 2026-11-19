// What this device tells the host when it pairs: its name, class, app bundle identifier and APNs environment.

import Foundation
import LisaAPIContract

/// What this device presents when it pairs (plan §6.3), besides the one-time code and its installation ID. The app
/// supplies it from its build configuration: the bundle identifier is the APNs topic, and the environment is
/// `development` for Debug builds and `production` for Release builds.
public struct PairingDevice: Hashable, Sendable {
    /// A name the owner recognizes, such as the device's name.
    public var name: String
    /// iPhone, iPad or Mac.
    public var deviceClass: DeviceClassValue
    /// The app's bundle identifier.
    public var appBundleID: String
    /// The APNs environment of this build.
    public var environment: APNsEnvironmentValue

    /// A device description.
    public init(name: String, deviceClass: DeviceClassValue, appBundleID: String, environment: APNsEnvironmentValue) {
        self.name = name
        self.deviceClass = deviceClass
        self.appBundleID = appBundleID
        self.environment = environment
    }
}
