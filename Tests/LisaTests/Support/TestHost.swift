// Test-only. Opens the production composition root (`LisaHost`) over one per-test scratch data directory, with a
// manual clock, no secrets and a network that refuses every client, and opens it again from the same directory to
// model a restart. Used by the integration and recovery suites (L03, L05, L07–L10, L12, L13, L15–L17, L19, L22,
// L23, §16.3).

import Foundation
import LisaAPIContract
import LisaCurl
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaHost
import LisaPorts
import LisaRuntime
import LisaSecrets
import LisaTime

/// The production host over a scratch data directory.
///
/// `open()` runs `LisaHost.open` exactly as `lisa serve` does. Only the platform services are the test's: the clock, an
/// empty secret store, a network whose every client is refused (so no adapter can reach anything, L02), and optionally
/// a scripted local-notification transport in place of the Mac app's notification center. Every delivery channel stays
/// a dry run unless a test changes the settings.
struct TestHost: Sendable {
    /// The owner's approved address.
    static let ownerAddress = "owner@example.com"
    /// Lisa's own mailbox and sending address.
    static let lisaAddress = "lisa@example.com"
    /// The owner's approved phone number.
    static let ownerNumber = "+15550100"

    /// The data directory, inside the test's scratch directory.
    let dataDirectory: URL
    /// The clock every service reads. It moves only when the test moves it.
    let clock: ManualWallClock
    /// The settings `open()` uses. A test may change them between restarts.
    var settings: HostSettings
    /// The local-notification transport the platform supplies, as the Mac app does; `nil` elsewhere.
    var localNotifications: (any LocalNotificationTransport)?

    /// - Parameters:
    ///   - scratch: the test's scratch directory; the data directory is `data` inside it.
    ///   - now: where the clock starts.
    ///   - owner: the configuration's owner settings (stored preferences are overlaid on them).
    ///   - sources: the configured sources.
    init(
        scratch: ScratchDirectory, now: Date, owner: OwnerSettings = TestHost.owner(), sources: [HostSource] = [],
        localNotifications: (any LocalNotificationTransport)? = nil
    ) {
        dataDirectory = scratch.path("data")
        clock = TestTime.clock(at: now)
        settings = HostSettings(
            dataDirectory: dataDirectory, applicationVersion: "0.0.0-test", ownerSettings: owner, model: .none,
            // Tokens are accepted for the synthetic companion app in the development environment; pushes stay dry runs.
            pushPolicy: PushRegistrationPolicy(
                allowedTopics: [SyntheticDevice.companionBundleID], allowedEnvironments: [.development]),
            sources: sources,
            // A failing source is retried after 30–60 seconds, so a test that moves the clock a minute on knows the
            // source is due again whatever the jitter.
            runtime: RuntimeOptions(retry: RetrySchedule(baseSeconds: 60, maxSeconds: 60)),
            emailSender: EmailSender(address: TestHost.lisaAddress, name: "Lisa"))
        self.localNotifications = localNotifications
    }

    /// Owner settings for tests: `zone`, every channel a dry run, and email enabled for the one approved address.
    static func owner(zone: TimeZoneID = TestTime.newYork) -> OwnerSettings {
        OwnerSettings(
            zone: zone, delivery: DeliverySettings(emailEnabled: true, approvedEmailAddresses: [ownerAddress]))
    }

    /// Opens the host: the lock, logging, the store (migrating it), settings, adapters, services, the runtime and the
    /// router, then recovery after downtime (plan §5.2, D-36).
    func open() throws -> LisaHost {
        try LisaHost.open(
            settings: settings,
            platform: HostPlatform(
                clock: clock, secrets: EnvironmentSecretStore(environment: [:]),
                localNotifications: localNotifications, mode: "test", network: TestHost.offlineNetwork))
    }

    /// Closes `host`, which releases the data-directory lock, and opens the same data directory again, as a restart
    /// does. The closed instance is released when `host` is replaced.
    func restart(_ host: inout LisaHost) throws {
        host.close()
        host = try open()
    }

    /// Moves the clock forward.
    func advance(minutes: Double) {
        clock.advance(by: minutes * 60)
    }

    /// Registers the embedding app's local-notification installation with notifications allowed, as the Mac app does
    /// when it starts with the host embedded, and returns its device ID.
    @discardableResult
    static func registerMac(on host: LisaHost, installationID: String = "synthetic-mac-installation") throws
        -> DeviceID
    {
        let record = try host.registerLocalInstallation(
            installationID: installationID, name: "Synthetic Mac", appBundleID: "com.example.lisa.mac",
            status: NotificationStatusRequest(authorization: .authorized))
        return DeviceID(record.deviceID)
    }

    /// Pairs a synthetic iPhone with a one-time code, registers a random push token for it and reports its permission,
    /// as the companion app does, and returns its device ID. Pushes to it are dry runs unless the push mode is live.
    @discardableResult
    static func pairPhone(on host: LisaHost, name: String = "Synthetic iPhone") throws -> DeviceID {
        let app = host.application
        let code = try app.createPairingCode(by: .localOwner)
        let issued = try app.pairDevice(
            code: code.code, installationID: SyntheticDevice.randomHex(bytes: 16), name: name, deviceClass: .iPhone,
            appBundleID: SyntheticDevice.companionBundleID, environment: .development)
        let id = issued.registration.id
        _ = try app.registerPushToken(
            deviceID: id, token: SyntheticDevice.randomToken(), environment: .development,
            topic: SyntheticDevice.companionBundleID)
        _ = try app.reportNotificationStatus(deviceID: id, authorization: .authorized, settings: [:])
        return id
    }

    /// A network whose every HTTP client is refused: no adapter can reach anything (L02).
    static let offlineNetwork = HostNetwork(
        makeHTTPClient: { purpose in throw NetworkRefused(purpose: purpose) }, mailTrustStorePath: nil,
        library: Result { () throws(CurlSetupError) in try CurlRuntime.library() })

    /// The error every HTTP client request for the offline network gets.
    struct NetworkRefused: Error, CustomStringConvertible {
        let purpose: HTTPClientPurpose
        var description: String { "the test network refuses every client (\(purpose))" }
    }
}
