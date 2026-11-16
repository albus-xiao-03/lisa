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

    /// Opens the host directly. Exits with code 4 when another runtime owns the data directory and 6 when the host
    /// refuses to start.
    static func open(_ options: HostOptions, mode: String = "cli") throws -> LisaHost {
        let settings = try settings(try configuration(options), options)
        do {
            return try LisaHost.open(
                settings: settings,
                platform: HostPlatform(secrets: CompositeSecretStore(), logToStandardError: false, mode: mode))
        } catch let error as RuntimeError {
            Output.error(error.description)
            throw LisaExit.dataDirectoryInUse
        } catch let error as HostError {
            Output.error(error.description)
            throw LisaExit.hostRefused
        }
    }

    /// Runs `body` with an open host and the owner's in-process client, closing the host afterwards.
    static func withOwner<T>(_ options: HostOptions, _ body: (LisaHost, LisaAPIClient) async throws -> T) async throws
        -> T
    {
        let host = try open(options)
        defer { host.close() }
        let client = LisaAPIClient(
            transport: host.ownerTransport, credentials: SessionCredentials(), requiresPairing: false)
        do {
            return try await body(host, client)
        } catch let error as ClientError {
            Output.error(error.description)
            throw LisaExit.failure
        }
    }
}

/// The local owner's in-process session needs no stored credential; this keeps the installation identity for the
/// length of one command.
final class SessionCredentials: CredentialStore {
    private let identity = Mutex<ClientIdentity?>(ClientIdentity(installationID: "lisa-cli"))

    func load() throws -> ClientIdentity? { identity.withLock { $0 } }
    func save(_ value: ClientIdentity) throws { identity.withLock { $0 = value } }
    func clear() throws { identity.withLock { $0 = nil } }
}
