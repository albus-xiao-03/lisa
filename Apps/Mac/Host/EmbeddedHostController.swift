// The embedded-host controller (UI-01, ARCH-03, D-50): it runs Lisa's host in the app over the owner's configuration
// and data directory, or connects to the running `lisa serve` that owns them, and points the app's one client at it.

import Foundation
import LisaConfig
import LisaHost
import LisaRuntime
import LisaSecrets
import Observation

/// Decides and runs the app's host (UI-01, ARCH-03).
///
/// - Starting reads the configuration as the `lisa` commands do and opens the host in process under the
///   data-directory lock, with this Mac's platform services: the secret store (`env:`, `file:` and `keychain:`
///   references, as `CompositeSecretStore` routes them), the local-notification transport and the mode `mac-app`. The
///   screens then use the host's in-process owner transport.
/// - When a running `lisa serve` owns the data directory, the app becomes its client through the owner endpoint file
///   and the loopback owner listener, exactly as `lisa` commands do (`ServeClientConnection`). Any other owner of the
///   data directory, such as a `lisa import` still running, leaves the app without a host until it tries again.
/// - The app never opens a second host on a data directory: the lock decides, and `stop` releases it only after the
///   host's processing loop has stopped. Nothing switches modes on its own; trying again does, at the owner's request.
@MainActor
@Observable
final class EmbeddedHostController {
    /// Where the screens get their data.
    private(set) var mode: HostMode = .starting
    /// Whether the host is being started or stopped.
    private(set) var isWorking = false
    /// The configuration last read, when it could be.
    private(set) var configuration: MacHostConfiguration?
    /// What recovery after the previous run skipped and why (REM-04), for the host started last.
    private(set) var recoveryNotes: [String] = []
    /// Configured capabilities this build of the host can't provide, for the host started last.
    private(set) var unavailableCapabilities: [String] = []
    /// Why `keychain:` secret references can't be resolved, when they can't.
    private(set) var keychainProblem: String?
    /// The owner listener's port on 127.0.0.1: this app's while it serves the API, or that of `lisa serve`.
    private(set) var ownerListenerPort: Int?

    @ObservationIgnored private var session: EmbeddedHostSession?
    @ObservationIgnored private let environment: LisaClientEnvironment
    @ObservationIgnored private let credentials: MacOwnerCredentials

    /// A controller that points `environment`'s transport at the host it runs or connects to, with the owner
    /// credential in `credentials` while it is a client.
    init(environment: LisaClientEnvironment, credentials: MacOwnerCredentials) {
        self.environment = environment
        self.credentials = credentials
    }

    /// The host running in this app, if any.
    var embeddedHost: LisaHost? { session?.host }

    // MARK: - Starting and stopping

    /// Runs the host in the app, or connects to the `lisa serve` that owns the data directory, or says why neither is
    /// possible. Does nothing while the host runs or another start or stop is in progress.
    func start() async {
        guard !isWorking, session == nil else { return }
        isWorking = true
        defer { isWorking = false }
        mode = .starting
        environment.setHostTransport(nil)
        credentials.setOwnerCredential(nil)
        ownerListenerPort = nil
        let loaded: MacHostConfiguration
        do throws(MacHostConfiguration.Problem) {
            loaded = try MacHostConfiguration.load()
        } catch {
            configuration = nil
            mode = .unavailable(reason: error.description, canRetry: true)
            return
        }
        configuration = loaded
        let settings = loaded.settings
        let platform = makePlatform()
        let opened = await Task.detached { EmbeddedHostController.open(settings: settings, platform: platform) }.value
        switch opened {
        case .opened(let host):
            let started = await EmbeddedHostSession.start(host)
            session = started
            recoveryNotes = host.recoveryNotes
            unavailableCapabilities = host.unavailable
            ownerListenerPort = started.ownerPort
            environment.setHostTransport(host.ownerTransport)
            mode = .embedded(deviceListener: Self.describe(settings.api), apiProblem: started.apiProblem)
        case .inUse(let owner):
            connect(settings: settings, platform: platform, owner: owner)
        case .refused(let reason):
            mode = .unavailable(reason: reason, canRetry: true)
        }
    }

    /// Tries again to get a host: connects to `lisa serve` again, for example after it restarted with a new owner
    /// credential, or runs the host here once it no longer runs. Does nothing while the host runs in this app.
    func retry() async {
        guard session == nil else { return }
        await start()
    }

    /// Stops the host running in the app and starts it again, for example after a secret it reads at start-up changed.
    func restart() async {
        guard session != nil else { return }
        guard await stop(grace: nil) else { return }
        await start()
    }

    /// Stops the host running in the app in reverse order of start-up, as `lisa serve` does, and leaves the screens
    /// without a host. Returns whether the data-directory lock was released (see `EmbeddedHostSession`).
    @discardableResult
    func stop(grace: Duration?) async -> Bool {
        guard let running = session, !isWorking else { return session == nil }
        isWorking = true
        defer { isWorking = false }
        environment.setHostTransport(nil)
        let released = await running.shutdown(grace: grace)
        session = nil
        ownerListenerPort = nil
        mode = .unavailable(reason: "Lisa's host was stopped.", canRetry: true)
        return released
    }

    /// The readiness checks of `lisa doctor` for the configuration last read, without opening the data directory or
    /// contacting any service; `nil` when there is no usable configuration.
    func readinessChecks() async -> [HostDiagnostic]? {
        guard let settings = configuration?.settings else { return nil }
        let platform = makePlatform()
        return await Task.detached { HostDiagnostics.check(settings: settings, platform: platform) }.value
    }

    // MARK: - Internals

    /// What opening the host gave.
    private enum OpenResult: Sendable {
        case opened(LisaHost)
        /// Another runtime owns the data directory.
        case inUse(owner: LockOwner?)
        case refused(String)
    }

    /// Opens the host under the data-directory lock; it reads and writes files, so it runs off the main actor.
    nonisolated private static func open(settings: HostSettings, platform: HostPlatform) -> OpenResult {
        do {
            return .opened(try LisaHost.open(settings: settings, platform: platform))
        } catch let error as RuntimeError {
            if case .dataDirectoryInUse(_, let owner) = error { return .inUse(owner: owner) }
            return .refused(error.description)
        } catch let error as HostError {
            return .refused("Lisa's host refused to start: \(error.description)")
        } catch {
            return .refused("Lisa's host could not be opened: \(error)")
        }
    }

    /// Becomes the client of the `lisa serve` that owns the data directory, or says why it can't.
    private func connect(settings: HostSettings, platform: HostPlatform, owner: LockOwner?) {
        do throws(ServeClientConnection.Refusal) {
            let connection = try ServeClientConnection.connect(settings: settings, platform: platform, owner: owner)
            credentials.setOwnerCredential(connection.credential)
            environment.setHostTransport(connection.transport)
            ownerListenerPort = connection.port
            mode = .client(processID: connection.processID, since: connection.since)
        } catch {
            mode = .unavailable(reason: error.description, canRetry: true)
        }
    }

    /// This Mac's platform services for the host. Without a bundle identifier, `keychain:` references are reported as
    /// unsupported, never resolved from anywhere weaker.
    private func makePlatform() -> HostPlatform {
        var keychain: (any SecretStore)?
        do {
            keychain = try KeychainSecretStore.forThisApp()
            keychainProblem = nil
        } catch {
            keychain = nil
            keychainProblem = "keychain: secrets can't be read: \(error)"
        }
        return HostPlatform(
            secrets: CompositeSecretStore(keychain: keychain), localNotifications: UserNotificationTransport(),
            mode: "mac-app")
    }

    /// Where paired devices reach the API, such as `127.0.0.1:8765 (plain HTTP on loopback)`.
    private static func describe(_ api: APIServerSettings) -> String {
        let protection =
            switch api.protection {
            case .none: "plain HTTP on loopback"
            case .native: "TLS"
            case .reverseProxy: "behind your reverse proxy"
            }
        return "\(api.bindAddress):\(api.port) (\(protection))"
    }
}
