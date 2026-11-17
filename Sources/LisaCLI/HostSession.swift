// Shared command plumbing: configuration paths, opening the host under the single-writer lock, and the owner's
// in-process API client.

import ArgumentParser
import Foundation
import LisaAPIContract
import LisaClient
import LisaConfig
import LisaHost
import LisaRuntime
import LisaSecrets
import Synchronization

/// Options every host command accepts.
struct HostOptions: ParsableArguments {
    @Option(
        name: .customLong("config"),
        help: "The configuration file (default: $LISA_CONFIG, then ~/.config/lisa/config.json5).")
    var configPath: String?

    @Option(name: .customLong("data-dir"), help: "Use this data directory instead of the configured one.")
    var dataDirectory: String?

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    var output: Output { Output(json: json) }

    /// The configuration file to read.
    var resolvedConfigPath: String {
        if let configPath { return (configPath as NSString).expandingTildeInPath }
        if let environment = ProcessInfo.processInfo.environment["LISA_CONFIG"], !environment.isEmpty {
            return (environment as NSString).expandingTildeInPath
        }
        return (("~/.config/lisa/config.json5") as NSString).expandingTildeInPath
    }
}

enum HostSession {
    /// Loads and validates the configuration, or exits with code 3 and every problem listed.
    static func configuration(_ options: HostOptions) throws -> LisaConfiguration {
        do {
            return try ConfigurationLoader.load(path: options.resolvedConfigPath)
        } catch {
            Output.error(error.description)
            throw LisaExit.invalidConfiguration
        }
    }

    /// The host settings for a configuration, with the data-directory override applied.
    static func settings(_ configuration: LisaConfiguration, _ options: HostOptions) throws -> HostSettings {
        var settings = try HostSettings(configuration: configuration, applicationVersion: LisaVersion.current)
        if let override = options.dataDirectory {
            settings.dataDirectory = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return settings
    }

    /// The platform services of a command-line host.
    static func platform(mode: String, logToStandardError: Bool = false) -> HostPlatform {
        HostPlatform(secrets: CompositeSecretStore(), logToStandardError: logToStandardError, mode: mode)
    }

    /// Opens the host directly. Exits with code 4 when another runtime owns the data directory and 6 when the host
    /// refuses to start.
    static func open(_ options: HostOptions, mode: String = "cli", logToStandardError: Bool = false) throws -> LisaHost
    {
        let settings = try settings(try configuration(options), options)
        do {
            return try LisaHost.open(
                settings: settings, platform: platform(mode: mode, logToStandardError: logToStandardError))
        } catch let error as RuntimeError {
            Output.error(error.description)
            throw LisaExit.dataDirectoryInUse
        } catch let error as HostError {
            Output.error(error.description)
            throw LisaExit.hostRefused
        }
    }

    /// Runs `body` with the owner's API client, closing any host it opened afterwards.
    ///
    /// When no other runtime owns the data directory, the host is opened directly and `body` receives it. When `lisa
    /// serve` owns it, the command connects to that host's loopback owner listener as a client instead (ARCH-03),
    /// and `body` receives no host. Any other owner of the data directory makes the command exit with code 4.
    static func withOwner<T>(_ options: HostOptions, _ body: (LisaHost?, LisaAPIClient) async throws -> T) async throws
        -> T
    {
        let settings = try settings(try configuration(options), options)
        let platform = platform(mode: "cli")
        let host: LisaHost
        do {
            host = try LisaHost.open(settings: settings, platform: platform)
        } catch let error as RuntimeError {
            guard case .dataDirectoryInUse(_, let owner) = error else {
                Output.error(error.description)
                throw LisaExit.dataDirectoryInUse
            }
            let client = try connectedClient(settings: settings, platform: platform, owner: owner, refusal: error)
            return try await run(body, host: nil, client: client)
        } catch let error as HostError {
            Output.error(error.description)
            throw LisaExit.hostRefused
        }
        defer { host.close() }
        let client = LisaAPIClient(
            transport: host.ownerTransport, credentials: SessionCredentials(), requiresPairing: false)
        return try await run(body, host: host, client: client)
    }

    private static func run<T>(
        _ body: (LisaHost?, LisaAPIClient) async throws -> T, host: LisaHost?, client: LisaAPIClient
    ) async throws -> T {
        do {
            return try await body(host, client)
        } catch let error as ClientError {
            Output.error(error.description)
            throw LisaExit.failure
        }
    }

    /// A client of the running host that owns the data directory, through its owner endpoint file. The endpoint must
    /// belong to the process holding the lock, so a stale file from an earlier run is never used.
    static func connectedClient(
        settings: HostSettings, platform: HostPlatform, owner: LockOwner?, refusal: RuntimeError
    ) throws -> LisaAPIClient {
        let file = OwnerEndpointFile(dataDirectory: settings.dataDirectory)
        let endpoint: OwnerEndpoint?
        do {
            endpoint = try file.read()
        } catch {
            Output.error("\(refusal.description); its owner endpoint cannot be read: \(error)")
            throw LisaExit.dataDirectoryInUse
        }
        guard let endpoint, let owner, owner.processID == endpoint.processID else {
            Output.error(
                "\(refusal.description); it does not serve the network API, so this command cannot connect to it")
            throw LisaExit.dataDirectoryInUse
        }
        let transport: LoopbackOwnerTransport
        do {
            transport = try LoopbackOwnerTransport(port: endpoint.port, network: platform.network)
        } catch {
            Output.error(error.description)
            throw LisaExit.hostRefused
        }
        return LisaAPIClient(
            transport: transport, credentials: SessionCredentials(credential: endpoint.credential),
            requiresPairing: false)
    }
}

/// The local owner's session needs no stored credential: in process none is used, and in client mode the running
/// host's owner credential is held for the length of one command only.
final class SessionCredentials: CredentialStore {
    private let identity: Mutex<ClientIdentity?>

    init(credential: String? = nil) {
        identity = Mutex(ClientIdentity(installationID: "lisa-cli", credential: credential))
    }

    func load() throws -> ClientIdentity? { identity.withLock { $0 } }
    func save(_ value: ClientIdentity) throws { identity.withLock { $0 = value } }
    func clear() throws { identity.withLock { $0 = nil } }
}
