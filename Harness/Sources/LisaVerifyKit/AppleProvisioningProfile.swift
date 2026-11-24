// An embedded provisioning profile as the preflight reads it (plan §10.8 "Identifiers read from the owner's signed
// products"): `security cms -D -i embedded.mobileprovision` on iPhone and iPad builds, or
// `Contents/embedded.provisionprofile` on the Mac. Only what the cases need is kept; nothing is exported.

import Foundation

/// The facts of an embedded provisioning profile.
public struct AppleProvisioningProfile: Sendable, Equatable {
    public let teamIdentifier: String?
    /// The profile's `application-identifier` (team prefix and bundle ID).
    public let applicationIdentifier: String?
    /// The profile's APNs environment under the platform's key, if it grants one.
    public let apsEnvironment: String?
    public let expiration: Date?
    /// The devices a development or ad hoc profile lists; nil when it lists none.
    public let provisionedDevices: [String]?
    public let provisionsAllDevices: Bool
    public let getTaskAllow: Bool

    /// `development`, `ad-hoc`, `enterprise` or `app-store`.
    public var kind: String {
        if provisionsAllDevices { return "enterprise" }
        if provisionedDevices != nil { return getTaskAllow ? "development" : "ad-hoc" }
        return "app-store"
    }

    /// Parses the decoded profile plist for `platform`.
    public static func parse(_ plist: Data, platform: ApplePlatform) throws(VerifyError) -> AppleProvisioningProfile {
        guard
            let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
            let profile = object as? [String: Any]
        else { throw .invalidInput("the provisioning profile isn't a property list") }
        let entitlements = profile["Entitlements"] as? [String: Any] ?? [:]
        return AppleProvisioningProfile(
            teamIdentifier: (profile["TeamIdentifier"] as? [String])?.first,
            applicationIdentifier: entitlements["application-identifier"] as? String
                ?? entitlements["com.apple.application-identifier"] as? String,
            apsEnvironment: entitlements[platform.apsEntitlementKey] as? String,
            expiration: profile["ExpirationDate"] as? Date,
            provisionedDevices: profile["ProvisionedDevices"] as? [String],
            provisionsAllDevices: profile["ProvisionsAllDevices"] as? Bool ?? false,
            getTaskAllow: entitlements["get-task-allow"] as? Bool ?? entitlements["com.apple.security.get-task-allow"]
                as? Bool
                ?? false)
    }
}
