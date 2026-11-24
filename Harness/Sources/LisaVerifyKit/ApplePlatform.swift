// The signing platforms the preflight distinguishes (plan §10.8): the Mac, and iOS for the iPhone and the iPad.

/// A signed product's platform.
public enum ApplePlatform: String, Sendable, Codable, CaseIterable {
    case macOS
    case iOS

    /// The platform's APNs entitlement: `com.apple.developer.aps-environment` on macOS, `aps-environment` on iOS
    /// and iPadOS.
    public var apsEntitlementKey: String {
        switch self {
        case .macOS: "com.apple.developer.aps-environment"
        case .iOS: "aps-environment"
        }
    }

    public var other: ApplePlatform { self == .macOS ? .iOS : .macOS }
}
