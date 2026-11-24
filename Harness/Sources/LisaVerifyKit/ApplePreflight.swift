// What stops a case before it runs (plan §10.8): a signed product and profile that don't match what the case needs —
// a missing platform APNs entitlement for a push case (or only the other platform's key), an environment other than
// the Core's APNs configuration, a topic other than the bundle ID, a profile that doesn't list the device, an expired
// or mismatched profile.

import Foundation

/// What a push case needs from the signed product.
public struct ApplePushRequirement: Sendable, Equatable {
    /// `development` or `production`, as the Core's APNs configuration says.
    public let environment: String
    /// The topic the Core will send to.
    public let topic: String

    public init(environment: String, topic: String) {
        self.environment = environment
        self.topic = topic
    }
}

/// The preflight's decisions about a signed product.
public enum ApplePreflight {
    /// Every reason the product can't run the case; empty when it can.
    public static func refusals(
        _ product: AppleSignedProduct, push: ApplePushRequirement?, deviceUDID: String?, now: Date = Date()
    ) -> [String] {
        var reasons: [String] = []
        guard let profile = product.profile else { return ["no embedded provisioning profile"] }
        if let expiration = profile.expiration, expiration <= now { reasons.append("the provisioning profile expired") }
        if let appID = profile.applicationIdentifier, appID != "*",
            !(appID.hasSuffix("." + product.bundleIdentifier) || appID.hasSuffix(".*"))
        {
            reasons.append("the profile's application identifier doesn't match \(product.bundleIdentifier)")
        }
        if let deviceUDID, product.platform == .iOS, !profile.provisionsAllDevices,
            let devices = profile.provisionedDevices,
            !devices.contains(deviceUDID)
        {
            reasons.append("the profile doesn't list this device")
        }
        if let push {
            let key = product.platform.apsEntitlementKey
            if let environment = product.apsEnvironment {
                if environment != push.environment {
                    reasons.append("\(key) is \(environment), but the Core's APNs configuration is \(push.environment)")
                }
                if let granted = profile.apsEnvironment, granted != environment {
                    reasons.append("the profile grants \(granted), the signature claims \(environment)")
                }
            } else if product.hasOtherPlatformAPSKeyOnly {
                reasons.append("only \(product.platform.other.apsEntitlementKey) is present; \(key) is needed")
            } else {
                reasons.append("the signed product has no \(key) entitlement")
            }
            if push.topic != product.apnsTopic {
                reasons.append("the Core's topic \(push.topic) isn't the bundle identifier \(product.apnsTopic)")
            }
        }
        return reasons
    }
}
