// A signed app as the preflight reads it (plan §10.8 "Identifiers read from the owner's signed products"): the
// entitlements from `codesign -d --entitlements - --xml`, `CFBundleIdentifier` from the built Info.plist, and the
// embedded profile. From these it derives, as R1's code does, the APNs topic, the Keychain service names
// (`Apps/Shared/Keychain/KeychainServiceName.swift`) and the R1 Mac client directory
// (`Apps/Shared/Storage/ProtectedStorageLocation.swift`). Build settings are never read.

import Foundation

/// The facts of one signed app.
public struct AppleSignedProduct: Sendable, Equatable {
    public let platform: ApplePlatform
    public let bundleIdentifier: String
    /// The APNs environment under this platform's own key, if the signature grants one.
    public let apsEnvironment: String?
    /// Whether only the other platform's APNs key is present.
    public let hasOtherPlatformAPSKeyOnly: Bool
    public let keychainAccessGroups: [String]
    public let applicationGroups: [String]
    public let appSandbox: Bool
    public let profile: AppleProvisioningProfile?

    public static func parse(
        platform: ApplePlatform, infoPlist: Data, entitlementsPlist: Data, profilePlist: Data?
    ) throws(VerifyError) -> AppleSignedProduct {
        guard
            let info = (try? PropertyListSerialization.propertyList(from: infoPlist, options: [], format: nil))
                as? [String: Any],
            let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty
        else { throw .invalidInput("the built Info.plist has no CFBundleIdentifier") }
        let entitlements =
            (try? PropertyListSerialization.propertyList(from: entitlementsPlist, options: [], format: nil))
            as? [String: Any] ?? [:]
        let own = entitlements[platform.apsEntitlementKey] as? String
        let other = entitlements[platform.other.apsEntitlementKey] as? String
        return AppleSignedProduct(
            platform: platform, bundleIdentifier: bundle, apsEnvironment: own,
            hasOtherPlatformAPSKeyOnly: own == nil && other != nil,
            keychainAccessGroups: entitlements["keychain-access-groups"] as? [String] ?? [],
            applicationGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            appSandbox: entitlements["com.apple.security.app-sandbox"] as? Bool ?? false,
            profile: try profilePlist.map { (data) throws(VerifyError) in
                try AppleProvisioningProfile.parse(data, platform: platform)
            })
    }

    /// The APNs topic: the bundle identifier.
    public var apnsTopic: String { bundleIdentifier }

    /// R1's Keychain service names for this app.
    public var keychainServices: (clientIdentity: String, secretPrefix: String) {
        ("\(bundleIdentifier).client-identity", "\(bundleIdentifier).secrets.")
    }

    /// R1's Mac client directory, inside the app's container when it is sandboxed; `home` is the user's home.
    public func r1ClientDirectory(home: String) -> String {
        let support =
            appSandbox
            ? "\(home)/Library/Containers/\(bundleIdentifier)/Data/Library/Application Support"
            : "\(home)/Library/Application Support"
        return "\(support)/\(bundleIdentifier)/Client"
    }
}
