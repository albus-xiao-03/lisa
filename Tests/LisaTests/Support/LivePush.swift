// Test-only. A test host whose push channel is live through the production APNs adapter (LisaAPNs's APNsPushTransport,
// which LisaHost builds as `lisa serve` does), with the scripted APNs client standing in for Apple's provider API and a
// synthetic signing key in the platform's secret store. Every other channel stays a dry run, and every other network
// client is refused, as on the test host (L02). Used by the live-push suites (L25, L29, L31, L32).

import Foundation
import LisaAPNs
import LisaDomain
import LisaHost
import LisaSecrets

/// The live push channel of one test host. Nothing is sent to Apple: every push reaches ``apns``.
struct LivePush: Sendable {
    /// Synthetic 10-character Team and Key IDs. Both are non-secret identifiers in APNs configuration.
    static let teamID = "SYNTHTEAM1"
    static let keyID = "SYNTHKEY01"
    /// The secret-store variable that holds the synthetic signing key.
    static let signingKeyVariable = "LISA_TEST_APNS_SIGNING_KEY"

    /// The substitute for the APNs provider API.
    let apns: ScriptedAPNsClient
    /// The synthetic signing key, PKCS#8 PEM, generated for this channel.
    let signingKey: String

    /// A channel with a newly generated signing key.
    init(apns: ScriptedAPNsClient = ScriptedAPNsClient()) async throws {
        self.apns = apns
        signingKey = try await SyntheticSigningKey.generate()
    }

    /// Sets `testHost` to push live through the APNs adapter, for `topics` in the development environment.
    func configure(_ testHost: inout TestHost, topics: Set<String> = [SyntheticDevice.companionBundleID]) {
        testHost.settings.ownerSettings.delivery.pushMode = .live
        testHost.settings.deliveryAdapters.apns = APNsSettings(
            teamID: Self.teamID, keyID: Self.keyID, signingKey: .environment(Self.signingKeyVariable),
            allowedTopics: topics, allowedEnvironments: [.development])
    }

    /// Opens `testHost` as ``TestHost/open()`` does, but with this channel's network and signing key.
    func open(_ testHost: TestHost) throws -> LisaHost {
        let apns = apns
        let network = HostNetwork(
            makeHTTPClient: { purpose in
                if case .apns = purpose { return apns }
                throw TestHost.NetworkRefused(purpose: purpose)
            }, mailTrustStorePath: nil, library: TestHost.offlineNetwork.library)
        let secrets = EnvironmentSecretStore(environment: [Self.signingKeyVariable: signingKey])
        return try LisaHost.open(
            settings: testHost.settings,
            platform: HostPlatform(
                clock: testHost.clock, secrets: secrets, localNotifications: testHost.localNotifications, mode: "test",
                network: network))
    }

    /// Closes `host` and opens the same data directory again with this channel, as a restart does.
    func restart(_ testHost: TestHost, _ host: inout LisaHost) throws {
        host.close()
        host = try open(testHost)
    }

    /// The push token the host holds for `device`, in whatever state, or `nil` when it holds none.
    static func token(of device: String, in host: LisaHost) throws -> String? {
        try host.application.record(DeviceRegistration.self, id: DeviceID(device))?.pushToken?.token.revealed
    }
}
