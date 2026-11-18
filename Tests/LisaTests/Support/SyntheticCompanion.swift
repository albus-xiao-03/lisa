// Test-only. A synthetic iPhone or iPad companion installation as the app keeps it: its identity file (standing in for
// Keychain), its durable offline queue file and its typed client over a transport the test chooses. It pairs through
// the API with a one-time code from the owner, registers a random push token and reports its permission, as the app
// does at pairing; relaunching it opens the same files again. Used by the client suites (L10, L21, L30) and later
// device suites.

import Foundation
import LisaAPIContract
import LisaClient
import LisaTime

/// A companion app installation on a synthetic device. Nothing it holds is a real credential or APNs token.
struct SyntheticCompanion: Sendable {
    /// The device's display name.
    let name: String
    let deviceClass: DeviceClassValue
    /// The identity file: installation ID, device ID and device credential (Keychain on a real device).
    let identityFile: URL
    /// The durable offline queue.
    let queueFile: URL
    /// The queue's limits and timing.
    let configuration: OfflineQueueConfiguration
    /// The clock the queue reads: the test host's, so queue times follow the test.
    let clock: ManualWallClock
    /// How the app reaches the host.
    private(set) var transport: any APITransport
    /// The app's typed client.
    private(set) var client: LisaAPIClient
    /// The app's durable offline queue.
    private(set) var queue: OfflineQueue

    /// A new installation whose files live in `scratch`, in a folder named after `name`.
    init(
        _ name: String, deviceClass: DeviceClassValue = .iPhone, in scratch: ScratchDirectory,
        transport: any APITransport, clock: ManualWallClock,
        configuration: OfflineQueueConfiguration = OfflineQueueConfiguration()
    ) throws {
        let folder = "companion-" + String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        self.name = name
        self.deviceClass = deviceClass
        identityFile = scratch.path(folder, "identity.json")
        queueFile = scratch.path(folder, "queue.json")
        self.configuration = configuration
        self.clock = clock
        self.transport = transport
        client = SyntheticCompanion.makeClient(transport: transport, identityFile: identityFile)
        queue = try SyntheticCompanion.makeQueue(queueFile: queueFile, configuration: configuration, clock: clock)
    }

    /// The app stopped and was launched again: a new client and queue over the same identity and queue files,
    /// optionally over another transport (such as a restarted host's).
    mutating func relaunch(transport newTransport: (any APITransport)? = nil) throws {
        if let newTransport { transport = newTransport }
        client = SyntheticCompanion.makeClient(transport: transport, identityFile: identityFile)
        queue = try SyntheticCompanion.makeQueue(queueFile: queueFile, configuration: configuration, clock: clock)
    }

    /// Pairs the installation with a one-time code the owner creates through `owner`, then registers a random push
    /// token for the companion app in the development environment and reports notifications allowed, as the app does
    /// at pairing. Returns the host's device ID.
    @discardableResult
    func pair(codeFrom owner: LisaAPIClient) async throws -> String {
        let code = try await owner.createPairingCode()
        let installation = try await client.installation()
        let device = try await client.pair(
            PairDeviceRequest(
                code: code.code, installationID: installation.installationID, name: name, deviceClass: deviceClass,
                appBundleID: SyntheticDevice.companionBundleID, environment: .development))
        _ = try await client.registerPush(
            PushRegistrationRequest(
                token: SyntheticDevice.randomToken(), environment: .development,
                topic: SyntheticDevice.companionBundleID))
        _ = try await client.reportNotificationStatus(NotificationStatusRequest(authorization: .authorized))
        return device.id
    }

    /// The installation's random identifier.
    func installationID() async throws -> String {
        try await client.installation().installationID
    }

    /// The stored device credential, for checks below the typed client; `nil` while unpaired.
    func credential() throws -> String? {
        try FileCredentialStore(fileURL: identityFile).load()?.credential
    }

    /// The handler the app's notification delegate calls for responses on this installation.
    var notificationActions: NotificationActionHandler {
        NotificationActionHandler(client: client, queue: queue)
    }

    private static func makeClient(transport: any APITransport, identityFile: URL) -> LisaAPIClient {
        LisaAPIClient(transport: transport, credentials: FileCredentialStore(fileURL: identityFile))
    }

    private static func makeQueue(
        queueFile: URL, configuration: OfflineQueueConfiguration, clock: ManualWallClock
    ) throws -> OfflineQueue {
        try OfflineQueue(
            storage: FileQueueStorage(fileURL: queueFile), configuration: configuration, clock: { clock.now() })
    }
}
