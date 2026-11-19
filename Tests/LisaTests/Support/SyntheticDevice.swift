// Test-only controlled substitute (plan §10): synthetic paired-device registrations with random tokens and verifiers,
// for the routing, privacy and Time Sensitive suites (L26, L31, L33) and later device tests (L25, L27–L30, L32).

import Foundation
import LisaDomain

/// Synthetic device registrations. Tokens and verifiers are random per call; none is a real APNs token or credential.
enum SyntheticDevice {
    /// A bundle identifier under the reserved `example` domain.
    static let companionBundleID = "com.example.lisa.companion"

    /// A paired, active installation that reported `authorization`. An `.apns` device gets an active random token for
    /// `environment`; a `.local` device (the Mac's embedded host) has none.
    static func registration(
        _ deviceClass: DeviceClass, name: String? = nil, transport: NotificationTransportKind = .apns,
        authorization: NotificationAuthorization = .authorized,
        preferences: DeviceNotificationPreferences = DeviceNotificationPreferences(),
        environment: APNsEnvironment = .development, now: Date, id: DeviceID = .random()
    ) -> DeviceRegistration {
        var device = DeviceRegistration(
            id: id, installationID: randomHex(bytes: 16), name: name ?? "Synthetic \(deviceClass.rawValue)",
            deviceClass: deviceClass, appBundleID: companionBundleID, environment: environment, transport: transport,
            credentialVerifier: randomHex(bytes: 32), now: now)
        device.authorization = authorization
        device.authorizationReportedAt = now
        device.preferences = preferences
        if transport == .apns {
            device.pushToken = PushTokenRecord(
                token: randomToken(), environment: environment, topic: companionBundleID, registeredAt: now)
        }
        return device
    }

    /// A random 32-byte token in lower-case hex, shaped like an APNs device token.
    static func randomToken() -> String {
        randomHex(bytes: 32)
    }

    /// `bytes` random bytes in lower-case hex.
    static func randomHex(bytes: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }
}
